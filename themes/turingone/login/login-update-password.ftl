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
<title>::TuringOne - Update Password</title>

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
</style>
</head>

<body>

<div class="background">
    <div class="card">

        <h1>Update password</h1>

        

        <form action="${url.loginAction}" method="post">

            <!-- CRITICAL -->
            <input type="hidden" name="credentialId" value="${credentialId!''}">

            <div class="input-group">
                <input type="password"
                       name="password-new"
                       placeholder="New password"
                       required>
            </div>

            <div class="input-group">
                <input type="password"
                       name="password-confirm"
                       placeholder="Confirm password"
                       required>
            </div>

            <button type="submit">Update password</button>
        </form>

    </div>
</div>

</body>
</html>
