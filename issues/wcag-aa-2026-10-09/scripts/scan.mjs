import puppeteer from 'puppeteer-core';
import { AxePuppeteer } from '@axe-core/puppeteer';
import fs from 'fs';
const pages = JSON.parse(fs.readFileSync('pages.json'));
const out = 'out'; fs.mkdirSync(out,{recursive:true});
const browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome',headless:'new',args:['--no-sandbox']});
const summary = [];
for (const [slug,url,shiny] of pages) {
  const p = await browser.newPage(); await p.setViewport({width:1366,height:900});
  await p.goto(url,{waitUntil:'networkidle2',timeout:90000});
  if (shiny) {
    const t0=Date.now();
    try { await p.waitForFunction(()=>window.Shiny && document.querySelectorAll('.dataTables_wrapper tbody tr').length>1,{timeout:240000,polling:2000}); } catch(e){ console.log(slug,'table wait timeout'); }
    try { await p.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy') && document.querySelectorAll('.recalculating').length===0,{timeout:180000,polling:2000}); } catch(e){ console.log(slug,'idle wait timeout'); }
    await new Promise(r=>setTimeout(r,5000));
    console.log(slug,'render secs',(Date.now()-t0)/1000, 'recalc', await p.evaluate(()=>document.querySelectorAll('.recalculating').length));
  }
  await p.screenshot({path:`${out}/${slug}.png`,fullPage:true});
  const res = await new AxePuppeteer(p).withTags(['wcag2a','wcag2aa','wcag21a','wcag21aa','best-practice']).analyze();
  fs.writeFileSync(`${out}/axe-${slug}.json`,JSON.stringify(res,null,1));
  // manual probes
  const probe = await p.evaluate(()=>{
    const q=s=>[...document.querySelectorAll(s)];
    const firstLinks=q('a[href]').slice(0,3).map(a=>({text:a.textContent.trim().slice(0,40),href:a.getAttribute('href')}));
    return {
      title:document.title, lang:document.documentElement.getAttribute('lang'),
      skipLink: firstLinks,
      landmarks:{main:q('main,[role=main]').length,nav:q('nav,[role=navigation]').length},
      h1:q('h1').map(h=>h.textContent.trim().slice(0,60)),
      headings:q('h1,h2,h3,h4,h5,h6').map(h=>h.tagName+':'+h.textContent.trim().slice(0,50)).slice(0,30),
      tables:q('table').map(t=>({id:t.id,cls:t.className.slice(0,40),caption:!!t.querySelector('caption'),th:t.querySelectorAll('th').length,thScope:t.querySelectorAll('th[scope]').length,rows:t.querySelectorAll('tbody tr').length})),
      inputs:q('input,select,textarea').filter(i=>i.type!=='hidden').map(i=>{const lab=i.id&&document.querySelector(`label[for="${CSS.escape(i.id)}"]`);return {id:i.id,type:i.type||i.tagName,label:lab?lab.textContent.trim().slice(0,40):null,aria:i.getAttribute('aria-label')||i.getAttribute('aria-labelledby'),placeholder:i.placeholder||null,visible:!!(i.offsetWidth||i.offsetHeight)}}),
      imgs:q('img').map(i=>({src:(i.getAttribute('src')||'').slice(0,60),alt:i.getAttribute('alt')})),
      svgs:q('svg').filter(s=>s.getBoundingClientRect().width>100).map(s=>({cls:(s.getAttribute('class')||'').slice(0,40),role:s.getAttribute('role'),label:s.getAttribute('aria-label'),title:!!s.querySelector('title')})),
      canvases:q('canvas').length, plots:q('.shiny-plot-output,.plotly,.html-widget').map(e=>({id:e.id,cls:e.className.slice(0,60),img:(e.querySelector('img')||{}).alt})),
      ariaLive:q('[aria-live]').map(e=>e.id+':'+e.getAttribute('aria-live')),
      shinyOutputs:q('.shiny-html-output,.shiny-text-output,.datatables').length,
      colorCues:q('td span[style*=color], td[style*=color], td span[style*=background], td[style*=background], .badge').slice(0,8).map(e=>({text:e.textContent.trim().slice(0,30),style:(e.getAttribute('style')||e.className).slice(0,80)})),
    };
  });
  // keyboard walk
  const tab=[];
  await p.evaluate(()=>{document.activeElement&&document.activeElement.blur(); window.scrollTo(0,0)});
  for (let i=0;i<25;i++){ await p.keyboard.press('Tab'); tab.push(await p.evaluate(()=>{const e=document.activeElement; if(!e||e===document.body) return {tag:'BODY'}; const cs=getComputedStyle(e); return {tag:e.tagName,id:e.id,text:(e.textContent||e.value||e.getAttribute('aria-label')||'').trim().slice(0,40),outline:cs.outlineStyle+' '+cs.outlineWidth,boxShadow:cs.boxShadow!=='none'}}));}
  probe.tabOrder=tab;
  fs.writeFileSync(`${out}/manual-${slug}.json`,JSON.stringify(probe,null,1));
  const v=res.violations.map(x=>({id:x.id,impact:x.impact,tags:x.tags.filter(t=>/^wcag\d|best/.test(t)).join(','),nodes:x.nodes.length,ex:x.nodes.slice(0,2).map(n=>n.target.join(' ')+' :: '+n.html.slice(0,140)),help:x.help}));
  summary.push({slug,url,title:probe.title,violations:v,incomplete:res.incomplete.map(x=>x.id+'('+x.nodes.length+')')});
  console.log(slug, v.map(x=>`${x.id}[${x.impact}]x${x.nodes}`).join(' '));
  await p.close();
}
fs.writeFileSync(`${out}/axe-summary.json`,JSON.stringify(summary,null,1));
await browser.close();
