import { checkdAgentPrompt, promptVersion } from './prompt.mjs';

export const actions = new Set(['create_task','update_task','archive_task','reschedule_task',
  'create_course','update_course','archive_course','update_course_day','create_plan','update_plan','archive_plan',
  'create_tag','update_tag','archive_tag','upsert_goal','archive_goal','update_profile','add_busy_period',
  'remove_busy_period','record_feedback','save_review']);
const maxBodyBytes = 18 * 1024 * 1024;
const maxModelReplyBytes = 512 * 1024;
const jsonHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
export class GatewayError extends Error {
  constructor(code, message, status=400) { super(message); this.code=code; this.status=status; }
}
const isObject = value => value && typeof value==='object' && !Array.isArray(value);
const fail = (code,message,status=400) => { throw new GatewayError(code,message,status); };

async function readModelPayload(response, signal) {
  const reader = response.body?.getReader();
  if (!reader) fail('invalid_model_reply','模型返回格式错误，请重试。',502);
  let onAbort;
  const aborted = new Promise((_, reject) => {
    onAbort = () => reject(new DOMException('Model response deadline reached', 'AbortError'));
    if (signal.aborted) onAbort(); else signal.addEventListener('abort', onAbort, {once:true});
  });
  const chunks=[]; let size=0;
  try {
    while (true) {
      const part = await Promise.race([reader.read(), aborted]);
      if (part.done) break;
      size += part.value.length;
      if (size > maxModelReplyBytes) fail('model_reply_too_large','模型回复过大，未修改数据。请缩小请求范围。',502);
      chunks.push(part.value);
    }
    const bytes = new Uint8Array(size); let offset=0;
    for (const part of chunks) { bytes.set(part, offset); offset += part.length; }
    try { return JSON.parse(new TextDecoder().decode(bytes)); }
    catch { fail('invalid_model_reply','模型返回格式错误，请重试。',502); }
  } catch (error) {
    void reader.cancel().catch(() => {});
    throw error;
  } finally {
    signal.removeEventListener('abort', onAbort);
  }
}

export function validateInput(body) {
  if (!isObject(body)) fail('invalid_request','请求格式不正确。');
  if (body.mode==='diagnose') return { mode:'diagnose',request:'请用简短中文确认连接可用，operations为空。',context:{revision:'diagnose'},history:[],attachments:[] };
  if (typeof body.request!=='string' || !body.request.trim() || body.request.length>12000) fail('invalid_request','请输入1至12000字的要求。');
  if (!isObject(body.context) || typeof body.context.revision!=='string' || JSON.stringify(body.context).length>240000) fail('invalid_context','上下文缺失或过长，请缩小日期范围。');
  const history=body.history??[];
  if (!Array.isArray(history) || history.length>12 || history.some(m=>!isObject(m)||!['user','assistant'].includes(m.role)||typeof m.text!=='string'||m.text.length>12000)) fail('invalid_history','对话记录格式不正确。');
  const attachments=body.attachments??[];
  if (!Array.isArray(attachments)||attachments.length>6) fail('attachment_limit','每次最多发送6个附件。');
  let imageCount=0,textCount=0;
  for (const item of attachments) {
    if (!isObject(item)||typeof item.name!=='string'||!item.name.trim()||item.name.length>256||typeof item.text!=='string'||!Array.isArray(item.images)||
        (item.kind!==undefined&&(typeof item.kind!=='string'||item.kind.length>40))||
        (item.note!==undefined&&(typeof item.note!=='string'||item.note.length>2000))) fail('invalid_attachment','附件格式不正确，名称、类型或说明过长。');
    textCount+=item.text.length;
    for (const image of item.images) {
      if (typeof image!=='string'||!/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(image)||image.length>4*1024*1024) fail('invalid_image','图片须为本地处理后的PNG、JPEG或WEBP。');
      imageCount++;
    }
  }
  if (imageCount>12||textCount>60000) fail('attachment_limit','最多12张图片或60000字附件正文，请拆分后发送。');
  return {request:body.request.trim(),context:body.context,history,attachments};
}

export function parseProposal(content,{revision,id}) {
  if (typeof content!=='string'||!content.trim()) fail('empty_model_reply','模型没有返回有效内容，请重试。',502);
  let text=content.trim();
  if (text.startsWith('```')) text=text.replace(/^```(?:json)?\s*/i,'').replace(/\s*```$/,'').trim();
  let value;
  try { value=JSON.parse(text); } catch {
    if (text.startsWith('{')||text.startsWith('[')) fail('invalid_proposal','模型提案不完整，未修改数据，请重试。',502);
    return {id,reply:text.slice(0,16000),contextRevision:revision,operations:[],questions:[],warnings:[]};
  }
  if (!isObject(value)||typeof value.reply!=='string'||value.reply.length>16000||
      Object.keys(value).some(k=>!['reply','operations','questions','warnings'].includes(k))) fail('invalid_proposal','模型提案格式不符合约定，未修改数据。',502);
  const operations=value.operations??[],questions=value.questions??[],warnings=value.warnings??[];
  if (!Array.isArray(operations)||operations.length>80||![questions,warnings].every(a=>Array.isArray(a)&&a.length<=20&&a.every(s=>typeof s==='string'&&s.length<=4000))) fail('invalid_proposal','模型提案过长或字段有误。',502);
  for (const op of operations) {
    if (!isObject(op)||!actions.has(op.action)||!isObject(op.data??{})||
        Object.keys(op).some(k=>!['action','entityId','data'].includes(k))||
        (op.entityId!==undefined&&(typeof op.entityId!=='string'||op.entityId.length>160))) fail('unsupported_operation','模型返回了不支持的操作，未修改数据。',502);
    const raw=JSON.stringify(op.data??{});
    if (raw.length>40000||/"(?:userId|user_id|ownerId|owner_id|level|parent|sql|timerSessions|completionStatus|completedAt|completed)"\s*:/.test(raw)) fail('protected_field','提案包含账号、层级或实际记录字段，已拒绝。',502);
  }
  return {id,reply:value.reply,contextRevision:revision,operations,questions,warnings};
}

export function buildModelRequest(input,{model,now}) {
  const context={...input.context,now:new Date(now.getTime()+8*3600000).toISOString().replace('Z','+08:00'),timezone:'Asia/Shanghai'};
  const text=JSON.stringify({request:input.request,context,attachments:input.attachments.map(a=>({name:a.name,kind:a.kind,text:a.text,note:a.note??'',imageCount:a.images.length}))});
  const images=input.attachments.flatMap(a=>a.images);
  return {model,temperature:0.2,max_tokens:6000,response_format:{type:'json_object'},stream:false,
    messages:[{role:'system',content:checkdAgentPrompt},...input.history.map(m=>({role:m.role,content:m.text})),
      {role:'user',content:images.length?[{type:'text',text},...images.map(url=>({type:'image_url',image_url:{url,detail:'high'}}))]:text}]};
}

export function createAgentHandler({config,authenticate,reserveQuota,fetcher=fetch,clock=()=>new Date(),newId=()=>crypto.randomUUID()}) {
  const origins=new Set((config.allowedOrigins??'').split(',').map(s=>s.trim()).filter(Boolean));
  return async request => {
    const origin=request.headers.get('origin');
    const cors=origin&&origins.has(origin)?{'access-control-allow-origin':origin,'vary':'Origin'}:{};
    const response=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{...jsonHeaders,...cors}});
    try {
      if (origin&&!origins.has(origin)) fail('origin_not_allowed','此网页来源尚未被管理员允许。',403);
      if (request.method==='OPTIONS') return new Response(null,{status:204,headers:{...cors,'access-control-allow-methods':'POST,OPTIONS','access-control-allow-headers':'authorization,apikey,content-type,x-client-info,x-checkd-dev-token'}});
      if (request.method!=='POST') fail('method_not_allowed','只支持POST请求。',405);
      const length=Number(request.headers.get('content-length')??0);
      if (length>maxBodyBytes) fail('request_too_large','请求超过大小限制，请减少附件。',413);
      const user=await authenticate(request);
      if (!user?.id) fail('auth_required','请先登录CheckD后使用云端智能体。',401);
      // Limit the streamed body as well as Content-Length; chunked uploads must
      // not evade the memory cap.
      const reader=request.body?.getReader(); const chunks=[]; let size=0;
      if (reader) while (true) {const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>maxBodyBytes){await reader.cancel();fail('request_too_large','请求超过大小限制。',413);}chunks.push(part.value);}
      const bytes=new Uint8Array(size);let offset=0;for(const part of chunks){bytes.set(part,offset);offset+=part.length;}
      let body;try {body=JSON.parse(new TextDecoder().decode(bytes));} catch {fail('invalid_request','请求不是有效JSON。');}
      const input=validateInput(body);
      if (!config.apiKey) fail('model_not_configured','管理员尚未配置模型密钥。',503);
      const target=new URL(config.baseUrl??'https://api.deepseek.com');
      if (target.protocol!=='https:'||target.username||target.password||target.search||target.hash) fail('invalid_server_config','服务端模型地址配置有误。',503);
      const model=config.model??'deepseek-flash';
      if (input.attachments.some(a=>a.images.length)&&config.supportsImages===false) fail('vision_unavailable','当前模型不支持图片，请先提取文字或更换服务端模型。',422);
      if (!await reserveQuota(user.id,request)) fail('quota_exceeded','请求较频繁或今日额度已用完，请稍后再试。',429);
      const endpoint=target.href.replace(/\/$/,'').replace(/\/chat\/completions$/,'')+'/chat/completions';
      const abort=new AbortController();const timeout=setTimeout(()=>abort.abort(),config.timeoutMs??90000);
      let payload;
      try {
        const upstream=await fetcher(endpoint,{method:'POST',headers:{'content-type':'application/json',authorization:'Bearer '+config.apiKey},body:JSON.stringify(buildModelRequest(input,{model,now:clock()})),signal:abort.signal});
        // Never relay a provider body: it may echo credentials or private inputs.
        if (!upstream.ok) {
          void upstream.body?.cancel().catch(() => {});
          fail(upstream.status===429?'model_busy':'model_unavailable',upstream.status===429?'模型服务繁忙，请稍后重试。':'模型服务暂不可用，请管理员检查配置。',upstream.status===429?429:502);
        }
        // The deadline covers response-body streaming too, not only headers.
        payload=await readModelPayload(upstream, abort.signal);
      } catch(error) {
        if(error instanceof GatewayError) throw error;
        if(error?.name==='AbortError') fail('model_timeout','模型响应超时，请保留输入后重试。',504);
        fail('model_unavailable','暂时无法连接模型服务，请稍后重试。',502);
      } finally {clearTimeout(timeout);}
      const choice=payload?.choices?.[0];
      if (choice?.finish_reason==='length') fail('truncated_proposal','模型回复被截断，未修改数据。请缩小计划范围后重试。',502);
      const proposal=parseProposal(choice?.message?.content,{revision:input.context.revision,id:newId()});
      return response({...proposal,promptVersion});
    } catch(error) {
      if (error instanceof GatewayError) return response({error:{code:error.code,message:error.message}},error.status);
      return response({error:{code:'gateway_error',message:'智能体服务暂不可用，请稍后重试。'}},503);
    }
  };
}
