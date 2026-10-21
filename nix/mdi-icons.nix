# The Material Design Icons font plus a name -> codepoint map, read from the
# font's own glyph names (they are the `mdi:` names Home Assistant uses).
{
  runCommand,
  material-design-icons,
  python3,
}:
runCommand "dms-sidebar-mdi-icons"
  {
    nativeBuildInputs = [ (python3.withPackages (p: [ p.fonttools ])) ];
  }
  ''
    mkdir -p $out
    font=${material-design-icons}/share/fonts/truetype/materialdesignicons-webfont.ttf
    cp $font $out/mdi.ttf
    python3 -I -c '
    import json, sys
    from fontTools.ttLib import TTFont
    cmap = TTFont(sys.argv[1]).getBestCmap()
    json.dump({name: cp for cp, name in cmap.items()}, open(sys.argv[2], "w"), separators=(",", ":"))
    ' $font $out/mdi.json
  ''
