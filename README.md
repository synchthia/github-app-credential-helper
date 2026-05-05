# How to

## 1. Place private key (GitHub Apps)

Place to `keys/private-key.pem`

## 2. Write config.env

- Set `GITHUB_APP_CLIENT_ID`

## 3. Set Helper

```bash
git config --global credential.https://github.com.helper $PWD/github-app-credential-helper.sh
git config --global credential.https://github.com.useHttpPath true
```

