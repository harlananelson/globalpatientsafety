import puppeteer from 'puppeteer-core';
import {snapshot} from 'lighthouse';
import fs from 'fs';
const pages=JSON.parse(fs.readFileSync('pages.json'));
const browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome',headless:'new',args:['--no-sandbox']});
for (const [slug,url] of pages){
  const p=await browser.newPage(); await p.setViewport({width:1366,height:900});
  const t0=Date.now();
  await p.goto(url,{waitUntil:'networkidle2',timeout:90000});
  try{await p.waitForFunction(()=>document.querySelectorAll('.dataTables_wrapper tbody tr').length>0 && document.querySelector('#app-timeline-timeline img'),{timeout:400000,polling:2000});}catch(e){console.log(slug,'timeout')}
  await new Promise(r=>setTimeout(r,10000));
  console.log(slug,'secs',(Date.now()-t0)/1000,'recalc',await p.evaluate(()=>[...document.querySelectorAll('.recalculating')].map(e=>e.id)));
  const r=await snapshot(p,{config:{extends:'lighthouse:default',settings:{onlyCategories:['accessibility']}}});
  fs.writeFileSync(`lh/lh-${slug}.report.json`,JSON.stringify(r.lhr,null,1));
  const {ReportGenerator}=await import('lighthouse/report/generator/report-generator.js');
  fs.writeFileSync(`lh/lh-${slug}.report.html`,ReportGenerator.generateReportHtml(r.lhr));
  const a=r.lhr.categories.accessibility;
  console.log(slug,'LH',Math.round(a.score*100),Object.entries(r.lhr.audits).filter(([k,v])=>v.score===0).map(([k])=>k).join(','));
  await p.close();
}
await browser.close();
