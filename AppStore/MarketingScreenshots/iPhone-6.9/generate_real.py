#!/usr/bin/env python3
"""SplitX App Store screenshots — real app snapshots framed at 1290x2796."""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1290, 2796
S = 2
HERE = os.path.dirname(os.path.abspath(__file__))
SNAP = os.path.join(HERE, "snapshots")
OUT = os.environ.get("OUT", HERE)
ICON = "/Users/sal/developer/sharedexpenses/AppIcons/appstore.png"

SF = "/System/Library/Fonts/SFNS.ttf"
_fc = {}
def F(weight, size):
    k = (weight, int(size*S))
    if k not in _fc:
        f = ImageFont.truetype(SF, max(1, int(size*S)))
        try: f.set_variation_by_name(weight)
        except Exception: pass
        _fc[k] = f
    return _fc[k]

GREEN=(94,199,154); BLUE=(91,155,241); PURPLE=(180,155,232)

class Pen:
    def __init__(self, img, u=1.0):
        self.img=img; self.d=ImageDraw.Draw(img); self.u=u; self.k=u*S
    def text(self,pos,s,weight,size,fill,anchor="la",spacing=4):
        self.d.text((pos[0]*self.k,pos[1]*self.k),s,font=F(weight,size*self.u),fill=fill,anchor=anchor,spacing=spacing*self.k)
    def tw(self,s,weight,size):
        return self.d.textlength(s,font=F(weight,size*self.u))/self.k
    def paste(self,im,pos):
        self.img.alpha_composite(im,(int(pos[0]*self.k),int(pos[1]*self.k)))

def gradient(c1,c2):
    g=Image.new("L",(1,H*S))
    for y in range(H*S): g.putpixel((0,y),int(255*(y/(H*S))))
    m=g.resize((W*S,H*S))
    return Image.composite(Image.new("RGB",(W*S,H*S),c2),Image.new("RGB",(W*S,H*S),c1),m).convert("RGBA")

def add_blobs(img,colors):
    b=Image.new("RGBA",img.size,(0,0,0,0)); d=ImageDraw.Draw(b)
    for fx,fy,fr,c in [(0.12,0.10,0.55,colors[0]),(0.95,0.28,0.5,colors[1]),(0.5,0.95,0.62,colors[0])]:
        cx,cy,rr=fx*W*S,fy*H*S,fr*W*S; d.ellipse([cx-rr,cy-rr,cx+rr,cy+rr],fill=c+(40,))
    img.alpha_composite(b.filter(ImageFilter.GaussianBlur(130)))

_ic={}
def rounded_icon(size,u=1.0):
    px=int(size*u*S)
    if px not in _ic:
        im=Image.open(ICON).convert("RGBA").resize((px,px),Image.LANCZOS)
        m=Image.new("L",(px,px),0); ImageDraw.Draw(m).rounded_rectangle([0,0,px,px],radius=int(px*0.225),fill=255)
        im.putalpha(m); _ic[px]=im
    return _ic[px]

def fit_cover(im, w, h):
    """Scale to COVER w x h then center-crop."""
    sw,sh=im.size; scale=max(w/sw,h/sh)
    im2=im.resize((int(sw*scale+0.5),int(sh*scale+0.5)),Image.LANCZOS)
    x=(im2.width-w)//2; y=(im2.height-h)//2
    return im2.crop((x,y,x+w,y+h))

def iphone_shot(path, K, scrW=430, aspect=2622/1206):
    scrH=scrW*aspect; bez=14; pad=58
    bodyW,bodyH=scrW+bez*2, scrH+bez*2
    totW,totH=bodyW+pad*2, bodyH+pad*2
    im=Image.new("RGBA",(int(totW*K*S),int(totH*K*S)),(0,0,0,0))
    sh=Image.new("RGBA",im.size,(0,0,0,0))
    ImageDraw.Draw(sh).rounded_rectangle([pad*K*S,(pad+20)*K*S,(pad+bodyW)*K*S,(pad+bodyH+20)*K*S],radius=int(80*K*S),fill=(10,14,40,120))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(int(26*K*S/10))))
    d=ImageDraw.Draw(im); ox,oy=pad*K*S,pad*K*S
    d.rounded_rectangle([ox-2,oy-2,ox+bodyW*K*S+2,oy+bodyH*K*S+2],radius=int(81*K*S),fill=(116,118,126))
    d.rounded_rectangle([ox,oy,ox+bodyW*K*S,oy+bodyH*K*S],radius=int(80*K*S),fill=(10,10,12))
    sw,shp=int(scrW*K*S),int(scrH*K*S)
    shot=fit_cover(Image.open(path).convert("RGBA"),sw,shp)
    mask=Image.new("L",(sw,shp),0); ImageDraw.Draw(mask).rounded_rectangle([0,0,sw,shp],radius=int(66*K*S),fill=255)
    im.paste(shot,(int(ox+bez*K*S),int(oy+bez*K*S)),mask)
    return im

def watch_shot(path, K, scrW=200, aspect=502/410):
    scrH=scrW*aspect; bez=16; pad=70
    bodyW,bodyH=scrW+bez*2, scrH+bez*2
    totW,totH=bodyW+pad*2, bodyH+pad*2
    im=Image.new("RGBA",(int(totW*K*S),int(totH*K*S)),(0,0,0,0))
    sh=Image.new("RGBA",im.size,(0,0,0,0))
    ImageDraw.Draw(sh).rounded_rectangle([pad*K*S,(pad+16)*K*S,(pad+bodyW)*K*S,(pad+bodyH+16)*K*S],radius=int(70*K*S),fill=(10,14,40,120))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(int(30*K*S/10))))
    d=ImageDraw.Draw(im); ox=pad*K*S; oy0=pad*K*S
    # crown + button
    d.rounded_rectangle([ox+bodyW*K*S-3*K*S,oy0+bodyH*K*S*0.30,ox+bodyW*K*S+10*K*S,oy0+bodyH*K*S*0.30+44*K*S],radius=int(6*K*S),fill=(80,80,84))
    d.rounded_rectangle([ox+bodyW*K*S-2*K*S,oy0+bodyH*K*S*0.52,ox+bodyW*K*S+7*K*S,oy0+bodyH*K*S*0.52+56*K*S],radius=int(4*K*S),fill=(60,60,64))
    d.rounded_rectangle([ox,oy0,ox+bodyW*K*S,oy0+bodyH*K*S],radius=int(70*K*S),fill=(12,12,14))
    d.rounded_rectangle([ox+5*K*S,oy0+5*K*S,ox+bodyW*K*S-5*K*S,oy0+bodyH*K*S-5*K*S],radius=int(66*K*S),fill=(24,24,26))
    sw,shp=int(scrW*K*S),int(scrH*K*S)
    shot=fit_cover(Image.open(path).convert("RGBA"),sw,shp)
    mask=Image.new("L",(sw,shp),0); ImageDraw.Draw(mask).rounded_rectangle([0,0,sw,shp],radius=int(52*K*S),fill=255)
    im.paste(shot,(int(ox+bez*K*S),int(oy0+bez*K*S)),mask)
    return im

def headline(p,head,sub):
    cx=W/2; yh=152
    p.text((cx,yh),head,"Heavy",59,(255,255,255),anchor="ma",spacing=6)
    nl=head.count("\n")+1
    p.text((cx,yh+nl*74+22),sub,"Medium",27,(255,255,255,235),anchor="ma",spacing=4)

def footer(p):
    ic=rounded_icon(58)
    total=58+14+p.tw("SplitX","Bold",34); x0=(W-total)/2; y=2652
    p.paste(ic,(x0,y-29))
    p.text((x0+72,y),"SplitX","Bold",34,(255,255,255,235),anchor="lm")

def place_phone(img,path,K,cy):
    ph=iphone_shot(path,K); pw,phh=ph.width/S,ph.height/S
    img.alpha_composite(ph,(int((W-pw)/2*S),int((cy-phh/2)*S)))

def compose(name,gc,bc,head,sub,build):
    img=gradient(*gc); add_blobs(img,bc)
    p=Pen(img); headline(p,head,sub); build(img,p)
    img.convert("RGB").resize((W,H),Image.LANCZOS).save(os.path.join(OUT,name),"PNG")
    print("wrote",name)

K=1.74; CY=1505
sp=lambda f: os.path.join(SNAP,f)

compose("01_group.png",(GREEN,BLUE),(GREEN,BLUE),
    "Split expenses\nwith your group","See who owes who, instantly.",
    lambda img,p:(place_phone(img,sp("IMG_0058.png"),K,CY),footer(p)))

compose("02_split.png",(BLUE,(74,110,210)),(BLUE,PURPLE),
    "Fair splits,\nevery time","Even shares or custom percentages.",
    lambda img,p:(place_phone(img,sp("IMG_0059.png"),K,CY),footer(p)))

def build_watch(img,p):
    w1=watch_shot(sp("incoming-8321829E-8E82-441B-8A83-CF9957A6EEE0.png"),2.2)  # + screen
    w2=watch_shot(sp("incoming-39BCDE29-1900-4088-BC89-34CF861136DE.png"),2.4)  # keypad
    img.alpha_composite(w1,(int((W*0.30-w1.width/S/2)*S),int((1245-w1.height/S/2)*S)))
    img.alpha_composite(w2,(int((W*0.66-w2.width/S/2)*S),int((1510-w2.height/S/2)*S)))
    footer(p)
compose("03_watch.png",(PURPLE,(120,92,196)),(PURPLE,BLUE),
    "Add it from\nyour wrist","Log an expense on Apple Watch — it syncs itself.",
    build_watch)

compose("04_offline.png",((46,176,149),(40,120,150)),(GREEN,BLUE),
    "Works offline,\nsyncs later","Add anywhere. SplitX catches up when you reconnect.",
    lambda img,p:(place_phone(img,sp("IMG_0060.png"),K,CY),footer(p)))

compose("05_add.png",((88,104,196),(96,80,168)),(BLUE,PURPLE),
    "Scan a receipt,\nsplit in seconds","Snap the receipt or type it in — even offline.",
    lambda img,p:(place_phone(img,sp("IMG_0061.png"),K,CY),footer(p)))

print("done")
