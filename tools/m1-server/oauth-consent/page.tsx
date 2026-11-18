import { redirect } from "next/navigation";
import { createCheckdSupabaseServerClient } from "./supabaseServer";

type Props = { searchParams: Promise<{ authorization_id?: string }> };

/**
 * Minimal CheckD OAuth consent page for the configured Supabase OAuth path.
 * Integrate this route into the HTTPS CheckD web auth host; it is not served
 * by the M1 MCP process and has not been deployed by this change.
 */
export default async function OAuthConsentPage({ searchParams }: Props) {
  const { authorization_id: authorizationId } = await searchParams;
  if (!authorizationId?.trim() || authorizationId.length > 512) {
    return <main><h1>无法授权</h1><p>授权请求缺少有效标识。</p></main>;
  }

  const supabase = await createCheckdSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    const returnTo = `/oauth/consent?authorization_id=${encodeURIComponent(authorizationId)}`;
    redirect(`/login?redirect=${encodeURIComponent(returnTo)}`);
  }

  const { data, error } = await supabase.auth.oauth.getAuthorizationDetails(authorizationId);
  if (error || !data) {
    return <main><h1>授权请求不可用</h1><p>请返回 WorkBuddy 重新发起连接。</p></main>;
  }
  if (!("authorization_id" in data)) {
    redirect(data.redirect_url);
  }

  const scopes = (data.scope ?? "").split(/\s+/).filter(Boolean);
  return (
    <main className="oauth-consent">
      <h1>授权 CheckD 连接</h1>
      <p>当前使用已登录的 CheckD 账号进行授权。</p>
      <p><strong>请求应用：</strong>{data.client.name}</p>
      <p><strong>回调地址：</strong>{data.redirect_uri}</p>
      <p>授权后，WorkBuddy 将代表当前账号访问 CheckD。数据接口仍使用此账号的 Supabase 身份并受数据库 RLS 限制。</p>
      <p>当前连接仅用于读取你的任务、课程和当前计划，并生成只读规划预览；不会通过此授权创建或修改任务、审批或应用计划。</p>
      <h2>请求权限</h2>
      {scopes.length ? <ul>{scopes.map((scope) => <li key={scope}>{scope}</li>)}</ul>
        : <p>授权服务器未提供权限说明。请勿批准，先检查 Connector scope 配置。</p>}
      {scopes.includes("offline_access") &&
        <p>offline_access 允许 WorkBuddy 在访问令牌到期后申请续期，直到你撤销授权。</p>}
      <p>以上 OAuth scope 不是数据库权限清单；任务及课程访问仍由 CheckD 服务端权限和 RLS 控制。</p>
      <form action="/api/oauth/decision" method="post">
        <input type="hidden" name="authorization_id" value={authorizationId} />
        <button type="submit" name="decision" value="approve" disabled={!scopes.length}>
          允许
        </button>
        <button type="submit" name="decision" value="deny">拒绝</button>
      </form>
    </main>
  );
}
