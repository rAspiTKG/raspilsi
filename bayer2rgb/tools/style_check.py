#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
コーディング規約の確認(SystemVerilog / Python)

  python3 style_check.py <ファイルまたはディレクトリ> ...

確認する規約
  - if / while は "if( 条件 )" の形。条件の中にスペースを入れない(文字列の中は除く)
  - for は "for( 初期化; 条件; 処理 )" の形。条件の中にスペースを入れない
  - SystemVerilog: if / else / for の後ろの begin は同じ行に書く。"end else" は同じ行に書く
  - インデントは半角スペース2つの倍数(タブを使わない)
  - 1行に ';' で区切った文を複数書かない(for の中と文字列・コメントは除く)
"""
import os
import re
import sys

SV_EXT = (".sv", ".svh", ".v")
PY_EXT = (".py",)


def strip_strings( s ):
  """文字列リテラルの中身を消す(スペースの判定から外す)"""
  return re.sub(r'"([^"\\]|\\.)*"', '""', s)


def strip_comment_sv( s ):
  s = strip_strings(s)
  i = s.find("//")
  if( i>=0 ):
    s = s[:i]
  return s


def strip_comment_py( s ):
  s = strip_strings(s)
  s = re.sub(r"'([^'\\]|\\.)*'", "''", s)
  i = s.find("#")
  if( i>=0 ):
    s = s[:i]
  return s


def paren_body( s, start ):
  """s[start] が '(' のとき、対応する ')' までの中身と終わりの位置を返す"""
  depth = 0
  for i in range(start, len(s)):
    if( s[i]=="(" ):
      depth += 1
    elif( s[i]==")" ):
      depth -= 1
      if( depth==0 ):
        return s[start+1:i], i
  return None, -1


# Python のキーワード演算子(in / not / and / or / is)の前後のスペースは文法上必要なので許す
PY_KW_SP = re.compile(r"\s*\b(not in|is not|in|is|and|or|not|if|else|for|lambda)\b\s*")


def check_cond( kw, body, errs, ln, lang="sv" ):
  if( not(body.startswith(" "))or(not(body.endswith(" "))) ):
    errs.append((ln, "%s( の後と ) の前にスペースを1つ入れる" % kw))
    return
  inner = body[1:-1]
  if( lang=="py" ):
    inner = PY_KW_SP.sub("_", inner)
  if( kw=="for" ):
    parts = inner.split(";")
    if( len(parts)==3 ):
      if( " " in parts[1].strip() ):
        errs.append((ln, "for の条件にスペースがある: %s" % parts[1].strip()))
    return
  if( " " in inner ):
    errs.append((ln, "%s の条件にスペースがある: %s" % (kw, inner)))


def check_sv( path ):
  errs = []
  in_block_comment = False
  with open(path, encoding="utf-8") as f:
    lines = f.read().split("\n")
  for n, raw in enumerate(lines, 1):
    if( "\t" in raw ):
      errs.append((n, "タブを使っている"))
    s = raw
    if( in_block_comment ):
      if( "*/" in s ):
        s = s[s.index("*/")+2:]
        in_block_comment = False
      else:
        continue
    if( ("/*" in s)and("*/" not in s) ):
      in_block_comment = True
      s = s[:s.index("/*")]
    code = strip_comment_sv(s)
    if( (code.strip()=="")or(code.lstrip().startswith("`")) ):
      continue
    ind = len(raw)-len(raw.lstrip(" "))
    if( ((ind%2)!=0)and(not(raw.lstrip().startswith(","))) ):
      errs.append((n, "インデントが2の倍数でない"))
    for m in re.finditer(r"\b(if|while|for)\s*\(", code):
      kw = m.group(1)
      if( code[m.start():m.end()]!=kw+"(" ):
        errs.append((n, "'%s(' の形にする" % kw))
        continue
      body, end = paren_body(code, m.end()-1)
      if( body is None ):
        continue
      check_cond(kw, body, errs, n)
      rest = code[end+1:].strip()
      if( (kw in ("if","for","while"))and(rest=="") ):
        errs.append((n, "%s の begin が次の行にある" % kw))
    if( re.match(r"^\s*else\b",code) ):
      errs.append((n, "else は end と同じ行に書く"))
    if( re.search(r"\belse\s*$",code) ):
      errs.append((n, "else の begin が次の行にある"))
    stmt = re.sub(r"\bfor\(.*\)", "", code)
    if( stmt.count(";")>1 ):
      errs.append((n, "1行に複数の文がある"))
  return errs


def check_py( path ):
  errs = []
  in_doc = False
  with open(path, encoding="utf-8") as f:
    lines = f.read().split("\n")
  for n, raw in enumerate(lines, 1):
    if( "\t" in raw ):
      errs.append((n, "タブを使っている"))
    # 三重引用符の文字列(説明文)は確認しない
    if( raw.count('"""')==1 ):
      in_doc = not(in_doc)
      continue
    if( in_doc or(raw.count('"""')==2) ):
      continue
    code = strip_comment_py(raw)
    if( code.strip()=="" ):
      continue
    for m in re.finditer(r"\b(if|elif|while)\s*\(", code):
      kw = m.group(1)
      body, end = paren_body(code, m.end()-1)
      if( body is None ):
        continue
      check_cond(kw, body, errs, n, "py")
    for m in re.finditer(r"\b(if|elif|while)\s+[^(\s]", code):
      errs.append((n, "%s の条件を ( ) で囲む" % m.group(1)))
    if( code.count(";")>0 ):
      errs.append((n, "';' で文を区切っている"))
  return errs


def main():
  targets = sys.argv[1:] if( len(sys.argv)>1 ) else ["."]
  files = []
  for t in targets:
    if( os.path.isdir(t) ):
      for root, _dirs, fs in os.walk(t):
        for fn in fs:
          if( fn.endswith(SV_EXT+PY_EXT) ):
            files.append(os.path.join(root, fn))
    else:
      files.append(t)
  n_err = 0
  for p in sorted(files):
    errs = check_sv(p) if( p.endswith(SV_EXT) ) else check_py(p)
    for ln, msg in errs:
      print("%s:%d: %s" % (p, ln, msg))
    n_err += len(errs)
  print("確認 %d ファイル、指摘 %d 件" % (len(files), n_err))
  return 0 if( n_err==0 ) else 1


if( __name__=="__main__" ):
  sys.exit(main())
