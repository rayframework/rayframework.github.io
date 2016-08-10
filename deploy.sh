git checkout master
git pull origin documentation
mkdocs build
cp -R site/* .
rm -rf site
git add .
git commit -am 'deploying'
git push origin master
git checkout documentation
