from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

W,H=2600,1600
img=Image.new('RGB',(W,H),(4,5,4))
d=ImageDraw.Draw(img)
# subtle bg noise/grid
for r in range(0,H,28):
    d.line((0,r,W,r),fill=(7,8,7),width=1)
for c in range(0,W,28):
    d.line((c,0,c,H),fill=(6,7,6),width=1)

def font(path,size):
    return ImageFont.truetype(path,size)
Inter='/usr/share/fonts/opentype/inter/Inter-Regular.otf'
InterM='/usr/share/fonts/opentype/inter/Inter-Medium.otf'
InterB='/usr/share/fonts/opentype/inter/Inter-Bold.otf'
InterEB='/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf'
Serif='/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf'
SerifB='/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'

f_title=font(InterB,42); f_sub=font(Inter,22); f_small=font(InterM,16)
f_card_title=font(Serif,40); f_card_sub=font(Serif,27); f_label=font(InterEB,11); f_caption=font(InterM,15)
f_note=font(InterM,18)

def rr(draw, xy, r, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)

def rgba(c,a=255): return (*c,a)

def blend(c1,c2,t): return tuple(int(c1[i]*(1-t)+c2[i]*t) for i in range(3))

cards=[
 {'key':'backlog','label':'BACKLOG','title':'Backlog','sub':'Task Board','cap':'Capture and organize\neverything.','bg':(8,32,51),'fg':(238,238,232),'accent':(187,169,141),'icon':'grid','mode':'backlog','dark':True},
 {'key':'planning','label':'PLANNING','title':'Planning','sub':'Sprint Planning','cap':'Plan work and align\nyour team.','bg':(239,228,207),'fg':(37,33,27),'accent':(154,118,81),'icon':'calendar','mode':'planning','dark':False},
 {'key':'todo','label':'TODO','title':'Todo','sub':'Task Queue','cap':'Prioritize and tackle\nwhat’s next.','bg':(248,247,243),'fg':(33,31,28),'accent':(142,109,86),'icon':'check','mode':'todo','dark':False},
 {'key':'inprogress','label':'IN PROGRESS','title':'In Progress','sub':'API Integration','cap':'Backend sync, alerts,\nand progress tracking.','bg':(248,247,243),'fg':(33,31,28),'accent':(177,132,114),'icon':'code','mode':'progress','dark':False},
 {'key':'review','label':'REVIEW','title':'Review','sub':'Mobile UI Audit','cap':'Evaluate experience\nand improve quality.','bg':(138,13,80),'fg':(255,238,246),'accent':(230,200,213),'icon':'phone','mode':'review','dark':True},
 {'key':'creative','label':'CREATIVE','title':'Creative','sub':'Launch Assets','cap':'Design assets that\ninspire and convert.','bg':(248,246,240),'fg':(33,31,28),'accent':(177,132,114),'icon':'pen','mode':'creative','dark':False},
 {'key':'testing','label':'TESTING','title':'Testing','sub':'User Testing','cap':'Validate with real users\nand iterate.','bg':(8,32,51),'fg':(238,238,232),'accent':(175,198,216),'icon':'users','mode':'testing','dark':True},
 {'key':'completed','label':'COMPLETED','title':'Completed','sub':'Release Done','cap':'Ship confidently.\nCelebrate progress.','bg':(168,182,159),'fg':(245,247,239),'accent':(77,111,73),'icon':'tick','mode':'completed','dark':False},
]

def draw_icon(draw,x,y,s,cfg):
    ac=cfg['accent']; fg=cfg['fg']; dark=cfg['dark']
    fill=blend(cfg['bg'], (255,255,255) if dark else (0,0,0), .08 if dark else .06)
    outline=blend(ac, cfg['bg'], .45)
    rr(draw,(x,y,x+s,y+s),int(s*.28),fill,outline,1)
    col=ac if not dark else blend(fg, ac, .28)
    cx=x+s/2; cy=y+s/2
    w=max(2,int(s/18))
    if cfg['icon']=='grid':
        a=s*.22; gap=s*.18
        for i in range(2):
            for j in range(2):
                draw.rounded_rectangle((x+s*.24+j*(a+gap),y+s*.24+i*(a+gap),x+s*.24+j*(a+gap)+a,y+s*.24+i*(a+gap)+a),radius=2,outline=col,width=w)
    elif cfg['icon']=='calendar':
        draw.rectangle((x+s*.27,y+s*.32,x+s*.73,y+s*.70),outline=col,width=w)
        draw.line((x+s*.27,y+s*.43,x+s*.73,y+s*.43),fill=col,width=w)
        draw.line((x+s*.38,y+s*.25,x+s*.38,y+s*.38),fill=col,width=w)
        draw.line((x+s*.62,y+s*.25,x+s*.62,y+s*.38),fill=col,width=w)
    elif cfg['icon']=='check':
        draw.ellipse((x+s*.25,y+s*.25,x+s*.75,y+s*.75),outline=col,width=w)
        draw.line((x+s*.38,y+s*.52,x+s*.48,y+s*.62,x+s*.66,y+s*.38),fill=col,width=w,joint='curve')
    elif cfg['icon']=='code':
        draw.line((x+s*.42,y+s*.30,x+s*.30,y+s*.50,x+s*.42,y+s*.70),fill=col,width=w)
        draw.line((x+s*.58,y+s*.30,x+s*.70,y+s*.50,x+s*.58,y+s*.70),fill=col,width=w)
        draw.line((x+s*.52,y+s*.29,x+s*.46,y+s*.72),fill=col,width=w)
    elif cfg['icon']=='phone':
        draw.rounded_rectangle((x+s*.36,y+s*.22,x+s*.64,y+s*.76),radius=4,outline=col,width=w)
        draw.ellipse((x+s*.47,y+s*.67,x+s*.53,y+s*.73),fill=col)
    elif cfg['icon']=='pen':
        draw.line((x+s*.31,y+s*.69,x+s*.68,y+s*.32),fill=col,width=w)
        draw.polygon([(x+s*.66,y+s*.30),(x+s*.74,y+s*.26),(x+s*.70,y+s*.36)],outline=col)
    elif cfg['icon']=='users':
        draw.ellipse((x+s*.30,y+s*.25,x+s*.50,y+s*.45),outline=col,width=w)
        draw.ellipse((x+s*.52,y+s*.30,x+s*.68,y+s*.46),outline=col,width=w)
        draw.arc((x+s*.25,y+s*.45,x+s*.57,y+s*.82),200,340,fill=col,width=w)
        draw.arc((x+s*.48,y+s*.48,x+s*.78,y+s*.83),200,340,fill=col,width=w)
    else:
        draw.ellipse((x+s*.25,y+s*.25,x+s*.75,y+s*.75),outline=col,width=w)
        draw.line((x+s*.36,y+s*.52,x+s*.47,y+s*.64,x+s*.67,y+s*.38),fill=col,width=w,joint='curve')

def draw_dots(draw,x,y,cfg,cols=5,rows=5,g=14,r=1.4):
    col=cfg['accent'];
    fill=rgba(col,105 if cfg['dark'] else 80)
    for i in range(rows):
        for j in range(cols):
            draw.ellipse((x+j*g-r,y+i*g-r,x+j*g+r,y+i*g+r),fill=fill)

def draw_card(cfg, size=(300,440), scale=1.0):
    cw,ch=size
    im=Image.new('RGBA',(cw,ch),(0,0,0,0)); dr=ImageDraw.Draw(im)
    bg=cfg['bg']; fg=cfg['fg']; ac=cfg['accent']
    fct=font(Serif, max(24, int(cw * .135)))
    fcs=font(Serif, max(18, int(cw * .090)))
    flb=font(InterEB, max(8, int(cw * .036)))
    fcp=font(InterM, max(12, int(cw * .050)))
    rr(dr,(0,0,cw-1,ch-1),28,rgba(bg,255),rgba(blend(bg,(255,255,255),.10),150),1)
    # subtle vignette
    overlay=Image.new('RGBA',(cw,ch),(0,0,0,0)); od=ImageDraw.Draw(overlay)
    od.ellipse((cw*.25,-ch*.25,cw*1.20,ch*.55),fill=(255,255,255,26 if not cfg['dark'] else 12))
    im=Image.alpha_composite(im,overlay); dr=ImageDraw.Draw(im)
    # Art per mode
    mode=cfg['mode']
    if mode in ['backlog','planning','testing','completed']:
        center=(cw*0.98,ch*0.98)
        stroke=rgba(ac,55 if not cfg['dark'] else 42)
        for k in range(8):
            r=48+k*22
            dr.arc((center[0]-r,center[1]-r,center[0]+r,center[1]+r),190,360,fill=stroke,width=1)
    if mode=='backlog':
        dr.ellipse((cw*.58,ch*.72,cw*.98,ch*1.04),fill=(14,53,96,145))
    if mode=='planning':
        dr.ellipse((cw*.62,ch*.78,cw*.96,ch*1.10),fill=rgba(ac,38))
    if mode=='todo':
        # large half circle + curved line and dot
        for k in range(1):
            r=cw*.42
            dr.arc((cw*.08,ch*.63,cw*.92,ch*1.19),200,340,fill=rgba(ac,95),width=1)
        dr.ellipse((cw*.32,ch*.88,cw*.70,ch*1.27),fill=rgba(ac,24))
        dr.ellipse((cw*.47,ch*.72,cw*.55,ch*.78),fill=rgba(ac,135))
    if mode=='progress':
        dr.rectangle((cw*.56,0,cw,ch),fill=(0,0,0,12))
        dr.ellipse((cw*.64,ch*.42,cw*1.02,ch*.70),outline=rgba(ac,115),width=1)
        dr.ellipse((cw*.64,ch*.56,cw*1.02,ch*.88),fill=(200,112,131,125))
        dr.line((cw*.83,ch*.62,cw*.83,ch*.88),fill=rgba(ac,130),width=1)
        dr.ellipse((cw*.82,ch*.88,cw*.84,ch*.90),fill=rgba(ac,150))
    if mode=='review':
        # magnifying glass lower
        dr.ellipse((cw*.46,ch*.66,cw*.88,ch*1.08),outline=(255,255,255,90),width=8)
        dr.line((cw*.47,ch*1.04,cw*.28,ch*1.24),fill=(255,255,255,120),width=12)
        dr.arc((cw*.70,ch*.54,cw*1.22,ch*1.02),160,330,fill=(255,255,255,15),width=1)
    if mode=='creative':
        center=(cw*1.02,ch*.43)
        for k in range(9):
            r=42+k*18
            dr.arc((center[0]-r,center[1]-r,center[0]+r,center[1]+r),95,275,fill=rgba(ac,45),width=1)
        dr.ellipse((cw*.42,ch*.70,cw*.72,ch*.96),fill=rgba(ac,35))
        dr.ellipse((cw*.33,ch*.82,cw*1.06,ch*1.31),fill=(8,32,51,255))
        draw_dots(dr,cw*.12,ch*.84,cfg,cols=4,rows=4,g=15,r=1.2)
    if mode=='testing':
        dr.ellipse((cw*.68,ch*.72,cw*1.02,ch*1.06),fill=(15,90,146,150))
    if mode=='completed':
        dr.ellipse((cw*.58,ch*.72,cw*.96,ch*1.08),fill=(63,100,70,88))
        dr.line((cw*.70,ch*.88,cw*.76,ch*.94,cw*.90,ch*.76),fill=(255,255,255,220),width=3,joint='curve')
    # icon/dots
    draw_icon(dr,28,28,56,cfg)
    if mode!='creative': draw_dots(dr,cw-92,44,cfg,cols=5,rows=5,g=14,r=1.2)
    # text
    dr.text((28,128),cfg['label'],font=flb,fill=rgba(ac if not cfg['dark'] else blend(fg,ac,.18),255),spacing=3)
    dr.text((28,176),cfg['title'],font=fct,fill=rgba(fg,255))
    dr.text((28,228),cfg['sub'],font=fcs,fill=rgba(fg,235))
    dr.line((28,286,68,286),fill=rgba(ac if not cfg['dark'] else fg,180),width=1)
    dr.multiline_text((28,318),cfg['cap'],font=fcp,fill=rgba(fg,215 if cfg['dark'] else 180),spacing=8)
    return im

# title
margin=80
d.text((margin,54),'v211 exact phase stack carousel',font=f_title,fill=(245,245,240))
d.text((margin,108),'All 8 phase cards stay arranged in one circular stack queue.',font=f_sub,fill=(155,155,148))

# phone frame left
px,py,pw,ph=80,170,680,1030
rr(d,(px,py,px+pw,py+ph),50,(2,2,2),(210,210,200),1)
rr(d,(px+10,py+10,px+pw-10,py+ph-10),42,(9,10,9),(55,55,50),1)
d.text((px+55,py+55),'Task Board',font=font(InterB,34),fill=(238,238,232))
d.text((px+55,py+97),'Phase cards → projects → phase tasks',font=font(Inter,20),fill=(150,150,144))
rr(d,(px+465,py+55,px+600,py+98),22,(245,242,236),None)
d.text((px+508,py+70),'SDUI',font=font(InterB,12),fill=(172,155,132))
# stack deck all cards
center=(px+345,py+560)
order=[7,6,5,4,3,2,1,0]  # back to front, front backlog
# offsets for all 8 cards in one stack
positions={0:(0,0,0,1.00),1:(42,12,2.5,0.958),2:(78,23,5.2,0.916),3:(112,34,7.8,0.878),4:(146,47,10,0.84),5:(-118,44,-9,0.86),6:(-80,28,-6,0.90),7:(-42,14,-3,0.95)}
for i in order:
    dx,dy,rot,sc=positions[i]
    card=draw_card(cards[i],(310,455))
    if sc!=1:
        card=card.resize((int(card.width*sc),int(card.height*sc)),Image.LANCZOS)
    card=card.rotate(rot,resample=Image.Resampling.BICUBIC,expand=True)
    shadow=Image.new('RGBA',card.size,(0,0,0,0)); sd=ImageDraw.Draw(shadow); sd.rounded_rectangle((8,8,card.width-8,card.height-8),radius=32,fill=(0,0,0,115 if i==0 else 65)); shadow=shadow.filter(ImageFilter.GaussianBlur(18))
    x=int(center[0]+dx-card.width/2); y=int(center[1]+dy-card.height/2)
    img.paste(shadow,(x,y+16),shadow)
    img.paste(card,(x,y),card)
# pager dots
for i in range(8):
    x=px+270+i*24
    r=6 if i==0 else 4
    fill=(236,226,206) if i==0 else (130,125,112)
    d.ellipse((x-r,py+930-r,x+r,py+930+r),fill=fill)
rr(d,(px+120,py+850,px+560,py+912),30,(247,244,237))
d.text((px+165,py+869),'Center card opens project list',font=f_note,fill=(48,45,40))
d.text((px+165,py+894),'Side card tap only focuses the queue',font=font(Inter,14),fill=(110,106,99))
# Right: 8 phase-card visual parity grid
startx=900; starty=250; cw,ch=360,520; gapx=42; gapy=42
d.text((startx,starty-92),'Reference-card parity',font=font(InterB,40),fill=(245,245,240))
d.text((startx,starty-48),'The carousel uses these exact 8 phase cards: no side status, no progress rail, no footer hint text.',font=font(Inter,22),fill=(155,155,148))
for idx,cfg in enumerate(cards):
    r=idx//4; col=idx%4
    x=startx+col*(cw+gapx); y=starty+r*(ch+gapy)
    card=draw_card(cfg,(cw,ch))
    shadow=Image.new('RGBA',card.size,(0,0,0,0)); sd=ImageDraw.Draw(shadow); sd.rounded_rectangle((5,5,cw-5,ch-5),radius=28,fill=(0,0,0,70)); shadow=shadow.filter(ImageFilter.GaussianBlur(16))
    img.paste(shadow,(x,y+16),shadow)
    img.paste(card,(x,y),card)

# Flow strip under cards
stripx, stripy = startx, 1420
rr(d,(stripx,stripy,stripx+1560,stripy+92),32,(245,242,236),(95,90,84),1)
d.text((stripx+34,stripy+23),'Tap flow preserved:',font=font(InterB,22),fill=(40,37,33))
d.text((stripx+220,stripy+23),'active phase card → project list for that phase → tasks inside selected project and phase',font=font(Inter,22),fill=(70,66,60))
d.text((stripx+34,stripy+56),'Empty phase still opens sheet/dialog with:  “No task was in this phase.”',font=font(InterM,17),fill=(105,99,92))

# footer
d.text((80,1545),'Updated static render preview. Actual APK uses Flutter SDUI renderer with circular modulo queue, hero sheet, and the same phase-project-task flow.',font=font(Inter,18),fill=(135,132,126))

out='/mnt/data/pmd_v211_exact_phase_stack_carousel_render.png'
img.save(out)
print(out)
