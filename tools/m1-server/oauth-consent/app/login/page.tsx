import LoginForm from "./loginForm";

type Props = { searchParams: Promise<{ redirect?: string; error?: string }> };

function safeReturnTo(value?: string) {
  if (!value || value.length > 2048 || !value.startsWith("/") || value.startsWith("//")
      || value.includes("\\")) return "/";
  try {
    const target = new URL(value, "https://checkd.invalid");
    if (target.origin !== "https://checkd.invalid" || target.pathname !== "/oauth/consent") {
      return "/";
    }
    const authorizationId = target.searchParams.get("authorization_id");
    if (!authorizationId?.trim() || authorizationId.length > 512) return "/";
    return `${target.pathname}?authorization_id=${encodeURIComponent(authorizationId)}`;
  } catch {
    return "/";
  }
}

export default async function LoginPage({ searchParams }: Props) {
  const params = await searchParams;
  return (
    <main style={{ maxWidth: 440, margin: "12vh auto", padding: 28,
      background: "white", borderRadius: 16, boxShadow: "0 8px 30px #302b2912" }}>
      <h1>登录 CheckD</h1>
      <p>登录后返回授权页面，确认 WorkBuddy 请求的账号和权限。</p>
      {params.error && <p role="alert">登录失败，请检查账号信息后重试。</p>}
      <LoginForm returnTo={safeReturnTo(params.redirect)} />
    </main>
  );
}
