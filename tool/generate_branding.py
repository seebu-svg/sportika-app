#!/usr/bin/env python3
"""Regenerate Sportika v1 assets. Requires Pillow: python3 -m pip install Pillow."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/branding'
MINT = '#36D8BD'
NAVY = '#09182D'
# Two forward-cut ribbons form an S. Coordinates use a 100-unit canvas.
RIBBONS = [[(77,24),(40,24),(24,48),(61,48),(69,36),(45,36),(48,32),(72,32)],
           [(23,76),(60,76),(76,52),(39,52),(31,64),(55,64),(52,68),(28,68)]]

def paths(color):
    return ''.join(f'<polygon fill="{color}" points="'+ ' '.join(f'{x},{y}' for x,y in p)+'"/>' for p in RIBBONS)

def svg(body, width=100, height=100):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{body}</svg>\n'

def render(size, background=None, ink=NAVY, rounded=False, inset=0):
    scale = 4
    im = Image.new('RGBA', (size*scale, size*scale), background or (0,0,0,0))
    d = ImageDraw.Draw(im)
    if rounded:
        d.rounded_rectangle((0,0,size*scale-1,size*scale-1),radius=size*scale*.22,fill=MINT)
    for polygon in RIBBONS:
        d.polygon([((inset+x*(1-2*inset/100))*size*scale/100,
                    (inset+y*(1-2*inset/100))*size*scale/100) for x,y in polygon],fill=ink)
    return im.resize((size,size),Image.Resampling.LANCZOS)

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'tokens.json').write_text(json.dumps({'version':1,'name':'Sportika','mint':MINT,'navy':NAVY,'white':'#FFFFFF'},indent=2)+'\n')
    (OUT/'symbol.svg').write_text(svg(paths(NAVY)))
    (OUT/'symbol-mint.svg').write_text(svg(paths(MINT)))
    (OUT/'app-icon.svg').write_text(svg(f'<rect width="100" height="100" fill="{MINT}"/>'+paths(NAVY)))
    render(1024,MINT).convert('RGB').save(OUT/'app-icon-1024.png')
    render(512,rounded=True).save(OUT/'brand-mark.png')
    render(512,ink=MINT).save(OUT/'symbol-mint.png')
    render(512).save(OUT/'symbol-navy.png')
    # Use the bundled brand font for portable PNG wordmarks.
    font_path=ROOT/'assets/fonts/barlow_condensed/BarlowCondensed-ExtraBold.ttf'
    font=ImageFont.truetype(str(font_path),144)
    for name,bg,ink in [('dark',NAVY,'#FFFFFF'),('light','#FFFFFF',NAVY)]:
        canvas=Image.new('RGB',(1200,360),bg)
        canvas.paste(render(240,rounded=True),(60,60),render(240,rounded=True))
        draw=ImageDraw.Draw(canvas)
        draw.text((340,75),'SPORTIKA',font=font,fill=ink)
        canvas.save(OUT/f'logo-{name}.png')
    # Android legacy launcher sizes; adaptive foreground stays inside safe area.
    res=ROOT/'android/app/src/main/res'
    for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
        dest=res/f'mipmap-{density}'
        dest.mkdir(parents=True,exist_ok=True)
        render(size,MINT).convert('RGB').save(dest/'ic_launcher.png')
    drawable=res/'drawable'
    def vector(ink,inset=0):
        nodes=[]
        for polygon in RIBBONS:
            pts=[(inset+x*(1-2*inset/100),inset+y*(1-2*inset/100)) for x,y in polygon]
            data='M'+' L'.join(f'{x:g},{y:g}' for x,y in pts)+' Z'
            nodes.append(f'    <path android:fillColor="{ink}" android:pathData="{data}"/>')
        return '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="100" android:viewportHeight="100">\n'+'\n'.join(nodes)+'\n</vector>\n'
    (drawable/'ic_brand_foreground.xml').write_text(vector(NAVY,8))
    splash = vector(NAVY).replace('android:width="108dp" android:height="108dp"', 'android:width="96dp" android:height="96dp"')
    tile = '<path android:fillColor="'+MINT+'" android:pathData="M22,0 H78 Q100,0 100,22 V78 Q100,100 78,100 H22 Q0,100 0,78 V22 Q0,0 22,0 Z"/>'
    splash = splash.replace('>\n', '>\n    '+tile+'\n', 1)
    (drawable/'splash_brand_mark.xml').write_text(splash)
    (drawable/'ic_brand_monochrome.xml').write_text(vector('#FFFFFF',8))
    for folder,mono in [('mipmap-anydpi-v26',False),('mipmap-anydpi-v33',True)]:
        dest=res/folder
        dest.mkdir(exist_ok=True)
        (dest/'ic_launcher.xml').write_text('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/brand_launcher_background"/>\n    <foreground android:drawable="@drawable/ic_brand_foreground"/>\n'+('    <monochrome android:drawable="@drawable/ic_brand_monochrome"/>\n' if mono else '')+'</adaptive-icon>\n')
    (res/'values/brand_colors.xml').write_text(f'<resources>\n    <color name="brand_launcher_background">{MINT}</color>\n</resources>\n')
    print('Generated branding and Android launcher icons.')

if __name__ == '__main__':
    main()
