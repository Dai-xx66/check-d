// Deploy with `supabase functions deploy recognize-course-schedule` and set
// OPENAI_API_KEY as a Supabase Edge Function secret. The mobile/web client
// never receives that key.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const apiKey = Deno.env.get('OPENAI_API_KEY');
  if (!apiKey) {
    return Response.json({ error: '识别服务尚未配置。' }, { status: 503, headers: corsHeaders });
  }
  try {
    const { imageBase64, mimeType } = await request.json();
    if (typeof imageBase64 !== 'string' || !['image/png', 'image/jpeg'].includes(mimeType)) {
      return Response.json({ error: '仅支持 PNG、JPG、JPEG 课程表图片。' }, { status: 400, headers: corsHeaders });
    }
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4.1-mini',
        input: [{ role: 'user', content: [
          { type: 'input_text', text: 'Read this university timetable. Return JSON only. Never invent missing values. courses: [{name,teacher?,classroom?,rules:[{weekday:1-7,sections:number[],weekRuleType: everyWeek|oddWeeks|evenWeeks|everyNWeeks|custom,startWeek?,endWeek?,intervalWeeks?,weekNumbers?,startsAtMinute?,endsAtMinute?}]}]. segments may contain {number,startsAtMinute,endsAtMinute} only if printed clearly. For uncertain week rules omit weekRuleType.' },
          { type: 'input_image', image_url: `data:${mimeType};base64,${imageBase64}` },
        ] }],
        text: { format: { type: 'json_object' } },
      }),
    });
    if (!response.ok) {
      return Response.json({ error: '识别服务暂时不可用。' }, { status: 502, headers: corsHeaders });
    }
    const payload = await response.json();
    const text = payload.output_text;
    if (typeof text !== 'string') throw new Error('Missing recognition output');
    return Response.json(JSON.parse(text), { headers: corsHeaders });
  } catch (_) {
    return Response.json({ error: '课程表识别失败，请使用清晰完整的截图重试。' }, { status: 422, headers: corsHeaders });
  }
});
