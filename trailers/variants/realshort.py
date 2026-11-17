exec(open('/tmp/jit/tr/v/common.py').read())
def cap(t, c): return (t[0], t[1], c, t[3], t[4])
CUT = [cap(SH["flowers"](), "Build, explore and fight in a VR sandbox"), cap(SH["vbuild"](), "Build anything, block by block"), SH["train"](),
       cap(SH["lava"](), "Descend into the Emberdeep"), cap(SH["battle"](), "Raid enemy bases"), SH["snowtank"](), SH["rocket"](), SH["sunsetslow"]()]
