const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const html=fs.readFileSync('index.html','utf8');
const source=html.slice(html.indexOf('async function submitNote()'),html.indexOf('function openNoteDialog()'));
for(const [status,message,expected] of [[201,'','便签已经留在岸边。'],[429,'duplicate_message','这张便签刚刚已经送达，请稍后再来。'],[429,'guestbook_rate_limited','岸边的便签有些多，请稍后再试。'],[503,'guestbook_paused','留言板暂时休息中，请稍后再来。']]){
 test(`submit ${status} ${message}`,async()=>{
  const input={value:'正常留言'},button={},notices=[];let loaded=0,request;
  const context={supabaseConfig:{url:'https://example.invalid',guestbookEnabled:true},supabaseReady:true,
   $:s=>s==='#noteInput'?input:s==='#noteWebsite'?{value:''}:button,
   toast:s=>notices.push(s),localStorage:{getItem:()=>0,setItem:()=>{}},Date,console,
   supabaseHeaders:x=>x,loadNotes:async()=>loaded++,fetch:async(url,opts)=>{request={url,opts};return {ok:status===201,status,json:async()=>({message})}}};
  vm.createContext(context);vm.runInContext(source,context);await context.submitNote();
  assert.equal(notices.at(-1),expected);assert.equal(button.disabled,false);
  assert.equal(request.opts.method,'POST');assert.deepEqual(JSON.parse(request.opts.body),{content:'正常留言'});
  assert.equal(input.value,status===201?'':'正常留言');assert.equal(loaded,status===201?1:0);
 });
}
