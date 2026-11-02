#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ブロック図の小さなライブラリ: 1つの座標定義から draw.io(mxfile)と SVG を作る

作図の決まり
  - クロックは緑、データパスは青、リセット・その他は黒
  - モジュールは黒線の四角。名前は左上に1行で書く(インスタンス名を含めて改行しない)
  - モジュールの中の論理のまとまり(FF と組み合わせ回路)は黒の破線の四角(dash=True)
  - ポートごとに線を引く。AXIなどのバスは少し太い線1本にまとめる
  - 線を分岐する点は丸で示す
"""
import html

BLACK = "#000000"
BLUE = "#1565C0"
GREEN = "#2E7D32"
GRAY = "#555555"
FONT = "Helvetica, Arial, 'Noto Sans CJK JP', 'Hiragino Kaku Gothic ProN', Meiryo, sans-serif"

THIN = 1.2
THICK = 3.2


def text_width( s, size, bold=False ):
  """文字列の幅の見積もり(px)。箱の大きさと文字の配置に使う"""
  w = 0.0
  for ch in s:
    o = ord(ch)
    if( o>=0x2E80 ):
      w += 1.0
    elif( ch in "il.,:;|!'()[]" ):
      w += 0.30
    elif( ch.isupper() ):
      w += 0.68
    elif( ch.isdigit() ):
      w += 0.56
    elif( ch==" " ):
      w += 0.28
    elif( ch=="_" ):
      w += 0.56
    else:
      w += 0.52
  return w*size*(1.08 if( bold ) else 1.0)


class Box:
  def __init__( self, x, y, w, h ):
    self.x = x
    self.y = y
    self.w = w
    self.h = h

  @property
  def r( self ):
    return self.x+self.w

  @property
  def b( self ):
    return self.y+self.h


class Diagram:
  def __init__( self, name, page_name, w, h ):
    self.name = name
    self.page_name = page_name
    self.w = w
    self.h = h
    self.boxes = []
    self.wires = []
    self.texts = []
    self.dots = []

  # ------------------------------------------------------------------
  # 基本図形
  # ------------------------------------------------------------------
  def box( self, x, y, w, h, title, size=11, bold=True, sw=THIN, dash=False ):
    tw = text_width(title, size, bold)
    if( (tw+12)>w ):
      raise ValueError("名前が1行に収まらない: %s (%.0f > %d)" % (title, tw+12, w))
    self.boxes.append(dict(x=x, y=y, w=w, h=h, title=title, size=size, bold=bold, sw=sw, dash=dash))
    return Box(x, y, w, h)

  def text( self, x, y, s, size=10, anchor="start", color=BLACK, bold=False, rot=0 ):
    self.texts.append(dict(x=x, y=y, s=s, size=size, anchor=anchor, color=color, bold=bold, rot=rot))

  def wire( self, pts, color=BLACK, width=THIN, arrow="end" ):
    """pts: 折れ点の並び。曲がりは2回まで"""
    bends = 0
    for i in range(1, len(pts)-1):
      a = pts[i-1]
      b = pts[i]
      c = pts[i+1]
      if( ((a[0]==b[0])and(b[1]==c[1]))or((a[1]==b[1])and(b[0]==c[0])) ):
        bends += 1
    if( bends>2 ):
      raise ValueError("曲がりが3回以上ある: %s" % (pts,))
    self.wires.append(dict(pts=pts, color=color, width=width, arrow=arrow))

  def dot( self, x, y, color=BLACK ):
    self.dots.append(dict(x=x, y=y, color=color))

  # ------------------------------------------------------------------
  # ポート名(線が箱に入る位置の内側に書く)
  # ------------------------------------------------------------------
  def port( self, box, side, pos, name, size=9.5, color=BLACK, inset=5 ):
    if( side=="L" ):
      self.text(box.x+inset, pos, name, size, "start", color)
    elif( side=="R" ):
      self.text(box.r-inset, pos, name, size, "end", color)
    elif( side=="T" ):
      self.text(pos, box.y+inset, name, size, "end", color, rot=-90)
    elif( side=="B" ):
      self.text(pos, box.b-inset, name, size, "start", color, rot=-90)
    else:
      raise ValueError(side)

  # ------------------------------------------------------------------
  # draw.io
  # ------------------------------------------------------------------
  def _drawio_cells( self ):
    cells = []
    n = [1]

    def nid():
      n[0] += 1
      return "%s-%d" % (self.name, n[0])

    for b in self.boxes:
      style = ("rounded=0;whiteSpace=nowrap;html=1;fillColor=#FFFFFF;strokeColor=#000000;"
               "strokeWidth=%.1f;align=left;verticalAlign=top;spacingLeft=6;spacingTop=1;"
               "fontSize=%d;fontStyle=%d;fontColor=#000000;%s" % (b["sw"], b["size"], 1 if( b["bold"] ) else 0,
                                                                   "dashed=1;" if( b["dash"] ) else ""))
      cells.append('<mxCell id="%s" value="%s" style="%s" vertex="1" parent="1">'
                   '<mxGeometry x="%g" y="%g" width="%g" height="%g" as="geometry"/></mxCell>'
                   % (nid(), html.escape(b["title"]), style, b["x"], b["y"], b["w"], b["h"]))
    for wv in self.wires:
      pts = wv["pts"]
      end = "block" if( wv["arrow"] in ("end","both") ) else "none"
      start = "block" if( wv["arrow"] in ("start","both") ) else "none"
      size = 8 if( wv["width"]>=2 ) else 6
      style = ("html=1;rounded=0;endArrow=%s;endFill=1;startArrow=%s;startFill=1;endSize=%d;startSize=%d;"
               "strokeColor=%s;strokeWidth=%.1f;" % (end, start, size, size, wv["color"], wv["width"]))
      mids = "".join('<mxPoint x="%g" y="%g"/>' % p for p in pts[1:-1])
      arr = '<Array as="points">%s</Array>' % mids if( mids ) else ""
      cells.append('<mxCell id="%s" style="%s" edge="1" parent="1"><mxGeometry relative="1" as="geometry">'
                   '<mxPoint x="%g" y="%g" as="sourcePoint"/><mxPoint x="%g" y="%g" as="targetPoint"/>%s'
                   '</mxGeometry></mxCell>' % (nid(), style, pts[0][0], pts[0][1], pts[-1][0], pts[-1][1], arr))
    for t in self.texts:
      tw = (text_width(t["s"], t["size"], t["bold"])*1.15)+6
      th = t["size"]+6
      align = {"start": "left", "end": "right", "middle": "center"}[t["anchor"]]
      if( t["rot"]==0 ):
        if( t["anchor"]=="start" ):
          x = t["x"]-3
        elif( t["anchor"]=="end" ):
          x = t["x"]-tw+3
        else:
          x = t["x"]-(tw/2)
        y = t["y"]-(th/2)
        rot = ""
      else:
        # -90度回転: 見た目は縦の帯。anchor "end" は (x,y) で文字が終わる(下向きに読む)
        if( t["anchor"]=="end" ):
          cy = t["y"]+(tw/2)-3
        elif( t["anchor"]=="start" ):
          cy = t["y"]-(tw/2)+3
        else:
          cy = t["y"]
        x = t["x"]-(tw/2)
        y = cy-(th/2)
        align = "center"
        rot = "rotation=-90;"
      style = ("text;html=1;strokeColor=none;fillColor=none;whiteSpace=nowrap;align=%s;verticalAlign=middle;"
               "fontSize=%g;fontColor=%s;fontStyle=%d;%s" % (align, t["size"], t["color"], 1 if( t["bold"] ) else 0, rot))
      cells.append('<mxCell id="%s" value="%s" style="%s" vertex="1" parent="1">'
                   '<mxGeometry x="%.1f" y="%.1f" width="%.1f" height="%.1f" as="geometry"/></mxCell>'
                   % (nid(), html.escape(t["s"]), style, x, y, tw, th))
    for d in self.dots:
      style = "ellipse;html=1;fillColor=%s;strokeColor=%s;" % (d["color"], d["color"])
      cells.append('<mxCell id="%s" value="" style="%s" vertex="1" parent="1">'
                   '<mxGeometry x="%g" y="%g" width="7" height="7" as="geometry"/></mxCell>'
                   % (nid(), style, d["x"]-3.5, d["y"]-3.5))
    return cells

  def drawio_diagram( self ):
    body = "".join(self._drawio_cells())
    return ('<diagram id="%s" name="%s"><mxGraphModel dx="%d" dy="%d" grid="1" gridSize="10" guides="1" '
            'tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="%d" pageHeight="%d" '
            'math="0" shadow="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>%s</root></mxGraphModel>'
            '</diagram>' % (self.name, html.escape(self.page_name), self.w, self.h, self.w, self.h, body))

  # ------------------------------------------------------------------
  # SVG(draw.io のデータを content 属性に埋め込むので draw.io でも開ける)
  # ------------------------------------------------------------------
  def svg( self, embed_drawio=True ):
    out = []
    content = ""
    if( embed_drawio ):
      mx = '<mxfile host="archdiag.py">%s</mxfile>' % self.drawio_diagram()
      content = ' content="%s"' % html.escape(mx, quote=True)
    out.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"%s>'
               % (self.w, self.h, self.w, self.h, content))
    out.append("<defs>")
    # SVG 1.1 の描画系は auto-start-reverse に対応しないので、始点用と終点用の矢印を分ける
    for col in (BLACK, BLUE, GREEN):
      cid = col.lstrip("#")
      for kind, sz in (("n", 9), ("t", 14)):
        out.append('<marker id="ae%s%s" viewBox="0 0 10 10" refX="9.5" refY="5" markerWidth="%d" markerHeight="%d" '
                   'markerUnits="userSpaceOnUse" orient="auto"><path d="M0,1 L10,5 L0,9 z" fill="%s"/>'
                   '</marker>' % (cid, kind, sz, sz, col))
        out.append('<marker id="as%s%s" viewBox="0 0 10 10" refX="0.5" refY="5" markerWidth="%d" markerHeight="%d" '
                   'markerUnits="userSpaceOnUse" orient="auto"><path d="M10,1 L0,5 L10,9 z" fill="%s"/>'
                   '</marker>' % (cid, kind, sz, sz, col))
    out.append("</defs>")
    out.append('<rect x="0" y="0" width="%d" height="%d" fill="#FFFFFF"/>' % (self.w, self.h))
    for b in self.boxes:
      dash = ' stroke-dasharray="6,4"' if( b["dash"] ) else ""
      out.append('<rect x="%g" y="%g" width="%g" height="%g" fill="#FFFFFF" stroke="#000000" stroke-width="%.1f"%s/>'
                 % (b["x"], b["y"], b["w"], b["h"], b["sw"], dash))
      out.append('<text x="%g" y="%g" font-family="%s" font-size="%g" font-weight="%s" fill="#000000" '
                 'dominant-baseline="middle">%s</text>'
                 % (b["x"]+6, b["y"]+(b["size"]*0.5)+4, FONT, b["size"], "bold" if( b["bold"] ) else "normal",
                    html.escape(b["title"])))
    for wv in self.wires:
      kind = "t" if( wv["width"]>=2 ) else "n"
      cid = wv["color"].lstrip("#")
      ms = ' marker-start="url(#as%s%s)"' % (cid, kind) if( wv["arrow"] in ("start","both") ) else ""
      me = ' marker-end="url(#ae%s%s)"' % (cid, kind) if( wv["arrow"] in ("end","both") ) else ""
      pts = " ".join("%g,%g" % p for p in wv["pts"])
      out.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linejoin="miter"%s%s/>'
                 % (pts, wv["color"], wv["width"], ms, me))
    for d in self.dots:
      out.append('<circle cx="%g" cy="%g" r="3.6" fill="%s"/>' % (d["x"], d["y"], d["color"]))
    for t in self.texts:
      tr = ' transform="rotate(%d %g %g)"' % (t["rot"], t["x"], t["y"]) if( t["rot"] ) else ""
      out.append('<text x="%g" y="%g" font-family="%s" font-size="%g" font-weight="%s" fill="%s" text-anchor="%s" '
                 'dominant-baseline="middle"%s>%s</text>'
                 % (t["x"], t["y"], FONT, t["size"], "bold" if( t["bold"] ) else "normal", t["color"], t["anchor"], tr,
                    html.escape(t["s"])))
    out.append("</svg>")
    return "\n".join(out)


def write_drawio( path, diagrams ):
  body = "".join(d.drawio_diagram() for d in diagrams)
  with open(path, "w", encoding="utf-8") as f:
    f.write('<mxfile host="archdiag.py" version="1.0">%s</mxfile>\n' % body)
