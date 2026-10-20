import json,re
ds=json.load(open('face_paths.json'))
s=open('index.src.html').read()
s=s.replace('{{TT}}',ds[0]).replace('{{O2}}',ds[1]).replace('{{O1}}',ds[2])
open('site/index.html','w').write(s)
print('ok',len(s))

# ---- privacy + 404 share header/footer with the landing page ----
import re
ds=json.load(open('face_paths.json'))
logo='<svg viewBox="0 0 883 430" fill="currentColor" aria-hidden="true"><path d="%s"/><path d="%s"/><path d="%s"/></svg>'%(ds[0],ds[1],ds[2])
def shell(title,desc,body,cls=''):
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title><meta name="description" content="{desc}"><meta name="theme-color" content="#07070a">
<link rel="icon" href="favicon.svg" type="image/svg+xml"><link rel="icon" href="favicon.ico" sizes="48x48">
<link rel="apple-touch-icon" href="assets/icons/apple-touch-icon.png">
<link rel="stylesheet" href="css/site.css?v=9"></head><body>
<header class="site-header"><a class="brand" href="index.html" aria-label="Otto, home">{logo}</a>
<nav class="nav" aria-label="Main"><a href="index.html#features">Features</a><a href="index.html#how">How it works</a><a href="index.html#new">What’s new</a><a href="index.html#faq">FAQ</a></nav>
<a class="btn btn-primary btn-sm" href="downloads/Otto.dmg">Download</a></header>
<main>{body}</main>
<footer class="site-footer" style="margin-top:80px"><div class="wrap"><div class="foot-legal"><span>© 2026 Otto</span><span><a href="index.html">Home</a> &nbsp; <a href="privacy.html">Privacy policy</a> &nbsp; <a href="mailto:marcello.zanetta1@gmail.com">Contact</a></span></div></div></footer>
</body></html>'''
src=open('/mnt/user-data/uploads/Otto/docs/privacy.html').read()
m=re.search(r'(<h1>.*?)\s*<footer>',src,re.S)
inner=m.group(1).replace('<div class="card">','<div class="card-note">')
open('site/privacy.html','w').write(shell('Privacy policy — Otto','How Otto handles your data: everything stays on your Mac.','<div class="wrap"><div class="doc">'+inner+'</div></div>'))
open('site/404.html','w').write(shell('Page not found — Otto','','<div class="wrap err"><div><h1>404</h1><p>This page isn’t on the list.</p><a class="btn btn-primary" href="index.html">Back to Otto</a></div></div>'))
print('privacy tail:',inner[-300:])
