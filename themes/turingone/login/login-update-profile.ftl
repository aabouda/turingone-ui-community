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

            <button type="submit">Save and continue</button>
        </form>

    </div>
</div>

</body>
</html>
