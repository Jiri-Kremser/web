# Resulting Website
https://jkremser.github.io

## Devel

```
# after cloning the repo
git submodule add -f -b master git@github.com:jkremser/jkremser.github.io.git public
git submodule update --init --recursive
```

```bash
hugo server -D
```

## Deploy
```bash
hugo && cd public && git add -A && git commit -m "update" && git push origin master
```
