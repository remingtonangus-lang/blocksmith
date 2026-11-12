import sys,os
from PIL import Image
d,out=sys.argv[1],sys.argv[2]
fs=sorted(os.listdir(d)); n=len(fs); pick=[fs[int(i*(n-1)/8)] for i in range(9)]
W=Image.new('RGB',(1920,1080))
for i,f in enumerate(pick): W.paste(Image.open(os.path.join(d,f)).convert('RGB').resize((640,360)),((i%3)*640,(i//3)*360))
W.save(out,quality=85)
