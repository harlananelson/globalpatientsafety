import puppeteer from 'puppeteer-core';
const b=await puppeteer.launch({executablePath:'/usr/bin/google-chrome',headless:'new',args:['--no-sandbox']});
const p=await b.newPage(); await p.setViewport({width:1366,height:900});
await p.goto('https://faers.mobi/?drug=tzield',{waitUntil:'networkidle2',timeout:90000});
await p.waitForFunction(()=>document.querySelectorAll('.dataTables_wrapper tbody tr').length>1,{timeout:400000,polling:2000});
await new Promise(r=>setTimeout(r,8000));
const info=await p.evaluate(()=>{
 const tr=[...document.querySelectorAll('.dataTables_wrapper tbody tr')];
 const th=[...document.querySelectorAll('.dataTables_wrapper thead th')];
 return {rowTabindex:tr.slice(0,3).map(r=>r.getAttribute('tabindex')), rowFocusableChildren:tr.slice(0,3).map(r=>r.querySelectorAll('a,button,input,[tabindex]').length),
   thAria:th.slice(0,5).map(h=>({t:h.textContent.trim(),aria:h.getAttribute('aria-label'),sort:h.getAttribute('aria-sort'),tabindex:h.getAttribute('tabindex')})),
   knownBadge:(document.getElementById('app-timeline-known_badge')||{}).outerHTML?.slice(0,300),
   cellsNovel:[...document.querySelectorAll('.dataTables_wrapper tbody td')].filter(td=>/^(novel|known|\?)$/.test(td.textContent.trim())).slice(0,3).map(td=>td.outerHTML.slice(0,200)),
   trend:[...document.querySelectorAll('.dataTables_wrapper tbody td')].filter(td=>/^(Accelerating|Declining|New|Stable|Rising)$/.test(td.textContent.trim())).slice(0,2).map(td=>td.outerHTML.slice(0,200)),
   plotAlt:(document.querySelector('#app-timeline-timeline img')||{}).alt,
   seriesTable:!!document.querySelector('#app-timeline-pair_series table'),
   rowCount:tr.length};
});
console.log(JSON.stringify(info,null,1));
// count tabs to reach first table row-ish element
let n=0,hit=null;
for(;n<120;n++){await p.keyboard.press('Tab'); const r=await p.evaluate(()=>{const e=document.activeElement;return e.closest('.dataTables_wrapper tbody')?'row':(e.closest('.dataTables_wrapper')? 'dt:'+e.tagName+':'+(e.getAttribute('aria-label')||e.placeholder||e.textContent).slice(0,30):null)}); if(r==='row'){hit=r;break;} if(r&&n<200) console.log(n,r);}
console.log('reached tbody via tab?',hit,'after',n);
// try Enter on a row via keyboard? check selection visual
await p.focus('#app-timeline-search_query').catch(()=>{});
const fr=await p.evaluate(()=>{const e=document.activeElement;const cs=getComputedStyle(e);return {id:e.id,outline:cs.outline,boxShadow:cs.boxShadow,border:cs.borderColor}});
console.log('search focus style',fr);
await b.close();
