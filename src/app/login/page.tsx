import { loginAction } from "@/lib/actions/auth";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <div className="login-shell">
      <div className="login-card">
        <div className="brand">
          <span className="brand-mark">
            <svg className="icon" viewBox="0 0 24 24" stroke="currentColor">
              <path d="M6 6l12 12M18 6 6 18" />
              <circle cx="7" cy="6" r="1.6" fill="currentColor" stroke="none" />
              <circle cx="7" cy="18" r="1.6" fill="currentColor" stroke="none" />
            </svg>
          </span>
        </div>
        <h1>Salon Manager</h1>
        <p className="sub">Entra con tu cuenta del salón</p>

        {error && <div className="alert error">Email o contraseña incorrectos.</div>}

        <form action={loginAction}>
          <div className="field">
            <label htmlFor="email">Email</label>
            <input id="email" name="email" type="email" required autoComplete="email" placeholder="marta@urbanbeauty.test" />
          </div>
          <div className="field">
            <label htmlFor="password">Contraseña</label>
            <input id="password" name="password" type="password" required autoComplete="current-password" placeholder="••••••••" />
          </div>
          <button type="submit" className="btn">Entrar</button>
        </form>

        <p className="login-hint">
          Datos de ejemplo tras <code>npm run db:seed</code>:<br />
          marta@urbanbeauty.test · laura@urbanbeauty.test · david@urbanbeauty.test<br />
          contraseña: <code>salon1234</code>
        </p>
      </div>
    </div>
  );
}
