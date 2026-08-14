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
<title>::TuringOne - Complete your profile</title>

<link rel="icon" href="${url.resourcesPath}/favicon.ico">
<link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap" rel="stylesheet">

<style>
body {
    margin: 0;
    font-family: 'Poppins', sans-serif;
}

.background {
    width: 100vw;
    height: 100vh;
    background: url("${url.resourcesPath}/bg.png") center/cover no-repeat;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
}

.background::before {
    content: "";
    position: absolute;
    inset: 0;
    background: linear-gradient(135deg, rgba(0,107,84,0.88), rgba(0,35,28,0.96));
}

.card {
    width: 420px;
    background: rgba(255,255,255,0.95);
    padding: 40px;
    border-radius: 24px;
    z-index: 1;
    text-align: center;
}

.card h1 {
    color: #006B54;
}

.alert {
    background: #fee2e2;
    color: #991b1b;
    padding: 12px;
    border-radius: 10px;
    margin-bottom: 16px;
}

.input-group {
    margin-bottom: 18px;
}

.input-group input {
    width: 100%;
    padding: 14px;
    border-radius: 12px;
    border: 1px solid #ddd;
}

button {
    width: 100%;
    padding: 14px;
    border-radius: 14px;
    border: none;
    background: linear-gradient(135deg, #0f9d7a, #004d3c);
    color: white;
    font-size: 16px;
}

/* ── Consentements RGPD ──────────────────────────────────────────────────
   Aligné à gauche : une case à cocher centrée est illisible. Chaque
   consentement est SÉPARÉ — les regrouper en une seule case invaliderait
   le consentement marketing au sens du RGPD (art. 7).                    */
.consent {
    text-align: left;
    margin-bottom: 16px;
}

.consent-title {
    font-size: 12px;
    font-weight: 600;
    color: #475569;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin: 18px 0 8px;
}

.consent label {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    font-size: 12.5px;
    line-height: 1.45;
    color: #334155;
    cursor: pointer;
}

.consent input[type="checkbox"] {
    width: 16px;
    height: 16px;
    margin: 1px 0 0;
    flex-shrink: 0;
    accent-color: #0f9d7a;
    cursor: pointer;
}

.consent a {
    color: #006B54;
    font-weight: 600;
}

.required-mark {
    color: #b91c1c;
    font-weight: 700;
}

.privacy-note {
    text-align: left;
    font-size: 11px;
    line-height: 1.5;
    color: #64748b;
    margin: 6px 0 20px;
}

.privacy-note a {
    color: #006B54;
}

.alert {
    background: rgba(220, 38, 38, 0.10);
    border: 1px solid rgba(220, 38, 38, 0.35);
    color: #b91c1c;
    border-radius: 10px;
    padding: 10px 12px;
    font-size: 13px;
    margin-bottom: 16px;
    text-align: left;
}
</style>
</head>

<body>

<div class="background">
    <div class="card">

        <h1>Complete your profile</h1>

        <#if message?has_content>
            <div class="alert">${kcSanitize(message.summary)?no_esc}</div>
        </#if>

        <form action="${url.loginAction}" method="post">

            <div class="input-group">
                <input type="text"
                       name="firstName"
                       placeholder="First name"
                       value="${(user.firstName!'')}"
                       autocomplete="given-name"
                       required>
            </div>

            <div class="input-group">
                <input type="text"
                       name="lastName"
                       placeholder="Last name"
                       value="${(user.lastName!'')}"
                       autocomplete="family-name"
                       required>
            </div>

            <div class="input-group">
                <input type="email"
                       name="email"
                       placeholder="Email address"
                       value="${(user.email!'')}"
                       autocomplete="email"
                       required>
            </div>

            <#-- Attribut déclaré dans le User Profile du realm par bootstrap.py.
                 Sans cette déclaration, Keycloak rejetterait silencieusement la valeur. -->
            <div class="input-group">
                <input type="text"
                       name="user.attributes.company"
                       placeholder="Company"
                       value="${(user.attributes.company!'')}"
                       autocomplete="organization"
                       required>
            </div>

            <#--
                Les deux consentements sont des attributs déclarés dans le User
                Profile du realm par bootstrap.py, comme `company`.

                Une case NON cochée n'est pas envoyée par le navigateur :
                l'absence de l'attribut vaut donc « false ». Le backend
                normalise en conséquence — pas de champ caché, qui rendrait la
                valeur ambiguë côté Keycloak.
            -->
            <div class="consent">
                <label>
                    <input type="checkbox"
                           name="user.attributes.termsAccepted"
                           value="true"
                           <#if (user.attributes.termsAccepted!'') == 'true'>checked</#if>
                           required>
                    <span>
                        I agree to the
                        <a href="https://getturingone.com/terms-of-service/" target="_blank" rel="noopener">Terms of Service</a>
                        and
                        <a href="https://getturingone.com/data-processing-agreement/" target="_blank" rel="noopener">Data Processing Agreement (DPA)</a>.
                        <span class="required-mark">*</span>
                    </span>
                </label>
            </div>

            <div class="consent">
                <div class="consent-title">Marketing Communications</div>
                <label>
                    <input type="checkbox"
                           name="user.attributes.newsletterOptIn"
                           value="true"
                           <#if (user.attributes.newsletterOptIn!'') == 'true'>checked</#if>>
                    <span>
                        I would like to learn more about testing, industry best
                        practices, and how to better use TuringOne. Please add me
                        to the newsletter!
                    </span>
                </label>
            </div>

            <p class="privacy-note">
                We use your details to create your account and, if you opt in, to
                send you our newsletter. You can unsubscribe at any time. See our
                <a href="https://getturingone.com/privacy-policy/" target="_blank" rel="noopener">Privacy Policy</a>.
            </p>

            <button type="submit">Save and continue</button>
        </form>

    </div>
</div>

</body>
</html>
