<#--
    TuringOne UI Community
    Copyright (C) 2026 TuringOne
    SPDX-License-Identifier: AGPL-3.0-only
-->
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>::TuringOne - Login</title>

<link rel="icon" type="image/x-icon" href="${url.resourcesPath}/favicon.ico">
<link rel="shortcut icon" href="${url.resourcesPath}/favicon.ico">


<!-- Google Font -->
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

<style>
/* ===== KEYCLOAK LAYOUT FIX ===== */
html, body, .login-pf, .login-pf-page, #kc-container {
    height: 100%;
    width: 100%;
    margin: 0;
}
body {
    font-family: 'Poppins', sans-serif;
    overflow: hidden;
}

.login-pf,
.login-pf-page,
#kc-container,
#kc-container-wrapper {
    width: 100%;
    height: 100%;
    min-height: 100vh;
}

/* ===== VARIABLES ===== */
:root {
    --primary: #006B54;
    --primary-light: #0f9d7a;
    --primary-dark: #004d3c;
    --glass: rgba(255,255,255,0.92);
    --text-muted: #7a8b85;
}

/* ===== GLOBAL ===== */
* { box-sizing: border-box; }

#kc-header,
#kc-header-wrapper,
#kc-locale {
    display: none;
}
#kc-container {
  display: flex;
}

/* ===== BACKGROUND ===== */
.background {
    width: 100vw;
    height: 100vh;
    background: url("${url.resourcesPath}/bg.png") center center / cover no-repeat fixed;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
    overflow: hidden;
}

.background::before {
    content: "";
    position: absolute;
    inset: 0;
    background: linear-gradient(135deg, rgba(0,107,84,0.88), rgba(0,35,28,0.96));
    z-index: 0;
}

/* ===== BRAND ===== */
.brand {
    position: absolute;
    top: 45px;
    font-size: 38px;
    font-weight: 600;
    color: white;
    letter-spacing: 0.5px;
    z-index: 2;
}

/* ===== CARD ===== */
.login-card {
    width: 420px;
    max-width: calc(100vw - 40px);
    background: var(--glass);
    padding: 45px 40px;
    border-radius: 26px;
    box-shadow: 0 40px 120px rgba(0,0,0,0.45);
    text-align: center;
    position: relative;
    z-index: 2;
    backdrop-filter: blur(14px);
}

/* ===== TITLES ===== */
.login-card h1 {
    color: var(--primary);
    font-size: 28px;
    margin-bottom: 6px;
}
.subtitle {
    color: var(--text-muted);
    font-size: 15px;
    margin-bottom: 30px;
}

/* ===== ALERT (Keycloak errors) ===== */
.alert {
    background: #fee2e2;
    color: #991b1b;
    padding: 12px;
    border-radius: 10px;
    margin-bottom: 18px;
    font-size: 14px;
}

/* ===== INPUTS ===== */
.input-group {
    position: relative;
    margin-bottom: 22px;
}

.input-group input {
    width: 100%;
    padding: 14px 42px 14px 50px;
    border-radius: 14px;
    border: 1px solid #e3e8e6;
    background: white;
    font-size: 15px;
    font-family: 'Poppins', sans-serif;
    outline: none;
    transition: all 0.3s ease;
}

.input-group input:focus {
    border-color: var(--primary);
    box-shadow: 0 0 0 3px rgba(0,107,84,0.15);
    transform: translateY(-1px);
}

/* icons */
.input-group::before {
    content: "";
    position: absolute;
    left: 16px;
    top: 50%;
    width: 18px;
    height: 18px;
    transform: translateY(-50%);
    opacity: 0.7;
    background-size: contain;
    background-repeat: no-repeat;
}

.input-email::before {
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' fill='%23006B54' viewBox='0 0 24 24'%3E%3Cpath d='M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4-8 5-8-5V6l8 5 8-5v2z'/%3E%3C/svg%3E");
}

.input-password::before {
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' fill='%23006B54' viewBox='0 0 24 24'%3E%3Cpath d='M12 17a2 2 0 100-4 2 2 0 000 4z'/%3E%3Cpath d='M17 8V7a5 5 0 00-10 0v1H5v12h14V8h-2zm-8-1a3 3 0 016 0v1H9V7z'/%3E%3C/svg%3E");
}

/* show/hide password */
.toggle-pass {
    position:absolute;
    right:14px;
    top:50%;
    transform:translateY(-50%);
    cursor:pointer;
    font-size:16px;
    opacity:0.6;
}
.toggle-pass:hover { opacity:1; }

/* ===== BUTTON ===== */
button {
    width: 100%;
    padding: 15px;
    border-radius: 16px;
    border: none;
    background: linear-gradient(135deg, var(--primary-light), var(--primary-dark));
    color: white;
    font-size: 16px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.3s ease;
    box-shadow: 0 6px 18px rgba(0,107,84,0.35);
}
button:hover {
    transform: translateY(-2px);
    box-shadow: 0 10px 26px rgba(0,107,84,0.45);
}

/* ===== FORGOT ===== */
.forgot {
    margin-top: 18px;
}
.forgot a {
    font-size: 14px;
    color: var(--text-muted);
    text-decoration: none;
}
.forgot a:hover {
    color: var(--primary);
    text-decoration: underline;
}

/* ===== LEGAL / OPEN SOURCE ===== */
.legal {
    position: absolute;
    bottom: 16px;
    left: 0;
    right: 0;
    text-align: center;
    font-size: 12px;
    color: rgba(255,255,255,0.6);
    z-index: 2;
}
.legal a {
    color: rgba(255,255,255,0.78);
    text-decoration: none;
}
.legal a:hover {
    color: #ffffff;
    text-decoration: underline;
}

/* ===== RESPONSIVE ===== */
@media (max-width: 480px) {
    .login-card { padding: 35px 25px; }
}

.brand-logo {
    display: flex;
    align-items: center;
    gap: 5px;
}

/* Three dots */
.logo-dots {
    display: flex;
    gap: 3px;
}

.logo-dots .dot {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: white;
    opacity: 0.9;
}

/* Text */
.logo-text {
    font-size: 50px;
    font-weight: 600;
    letter-spacing: 0.5px;
    color: white;
}

</style>
</head>

<body>
<div class="background">

    <div class="brand brand-logo">
    <span class="logo-dots">
        <span class="dot"></span>
        <span class="dot"></span>
        <span class="dot"></span>
    </span>
    <span class="logo-text">TuringOne</span>
</div>


    <div class="login-card">

        <h1>Welcome</h1>
        <p class="subtitle">Access your secure workspace</p>

        <!-- Keycloak error messages -->
        <#if message?has_content>
            <div class="alert">
                ${kcSanitize(message.summary)?no_esc}
            </div>
        </#if>

        <form action="${url.loginAction}" method="post">

            <div class="input-group input-email">
                <input type="text" name="username"
                       value="${(login.username!'')}"
                       placeholder="Email address"
                       required>
            </div>

            <div class="input-group input-password">
                <input id="password" type="password"
                       name="password"
                       placeholder="Password"
                       required>
                <span class="toggle-pass" onclick="togglePassword()">👁</span>
            </div>

            <button type="submit">Sign in</button>
        </form>

        <#if realm.resetPasswordAllowed>
        <div class="forgot">
            <a href="${url.loginResetCredentialsUrl}">
                Forgot your password?
            </a>
        </div>
        </#if>

    </div>

    <div class="legal">
        <a href="https://github.com/GetTuringOne/turingone-ui-community/blob/main/LICENSE"
           target="_blank" rel="noopener noreferrer">Open Source License — AGPL-3.0-only</a>
        &middot;
        <a href="https://github.com/GetTuringOne/turingone-ui-community"
           target="_blank" rel="noopener noreferrer">Source Code</a>
    </div>
</div>

<script>
function togglePassword() {
  const p = document.getElementById("password");
  p.type = (p.type === "password") ? "text" : "password";
}
</script>

</body>
</html>
