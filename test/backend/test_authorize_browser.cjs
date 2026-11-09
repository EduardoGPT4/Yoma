// Optional real-Chromium regression; invoked by test_myanimelist.py when
// YOMASHI_BROWSER_TESTS=1. PLAYWRIGHT_MODULE can name an installed module path.
// Uses a fresh browser profile and never signs in to a MAL account.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async () => {
  const browser = await chromium.launch({channel:process.env.YOMASHI_BROWSER_CHANNEL || 'chrome',headless:true});
  const context = await browser.newContext({viewport:{width:390,height:844},userAgent:'Mozilla/5.0 YomaShi browser verification'});
  const page = await context.newPage();
  const base = process.env.YOMASHI_TEST_BASE;
  if(!base)throw new Error('An explicit test base URL is required');
  let pair, destinationRequested=false, postStatus=0;
  const policyErrors=[];
  page.on('request',r=>{if(new URL(r.url()).hostname==='myanimelist.net')destinationRequested=true;});
  page.on('response',r=>{
    if(r.request().method()==='POST' && new URL(r.url()).pathname.endsWith('/yomashi-connect.php'))postStatus=r.status();
  });
  page.on('console',m=>{if(m.text().includes('form-action'))policyErrors.push('form-action');});
  try {
    if(base.startsWith('https:')) {
      await page.goto(base+'release-health.php',{waitUntil:'domcontentloaded',timeout:45000});
      await page.waitForFunction(()=>document.body.innerText.trim().startsWith('{'),null,{timeout:45000});
    }
    const started=await context.request.post(base+'yomashi-api.php',{data:{action:'start'}});
    if(!started.ok())throw new Error('Pairing HTTP '+started.status());
    pair=await started.json();
    const response=await page.goto(base+'yomashi-connect.php?device='+pair.device_id,{waitUntil:'networkidle'});
    const policy=response.headers()['content-security-policy'] || '';
    const requested=page.waitForRequest(r=>new URL(r.url()).hostname==='myanimelist.net',{timeout:7000}).catch(()=>null);
    await page.getByRole('button',{name:'Autorizar en MyAnimeList',exact:true}).click({noWaitAfter:true});
    await requested;
    const result={destination_requested:destinationRequested,form_post_status:postStatus,policy_errors:policyErrors,policy};
    console.log(JSON.stringify(result));
    if(!destinationRequested || postStatus!==303)throw new Error('Authorization navigation was blocked');
  } finally {
    try {
      if(pair) {
        const revoked=await context.request.post(base+'yomashi-api.php',{data:{action:'disconnect'},headers:{'X-YomaShi-Token':pair.device_token}});
        if(!revoked.ok())throw new Error('Test connection could not be revoked');
      }
    } finally {await browser.close();}
  }
})().catch(e=>{console.error(e.message);process.exitCode=1;});
