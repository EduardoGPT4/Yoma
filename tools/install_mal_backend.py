"""Install only the YomaShi extension into the owner's existing YomaTV web source.

Does not read credentials or publish anything. Deploy with that site's immutable
release workflow after running the backend verification suite.
"""
from pathlib import Path
import argparse

ROOT = Path(__file__).resolve().parents[1]

def install(web: Path):
    htdocs = web / 'htdocs'
    if not (htdocs / 'private/mal-http.php').is_file():
        raise RuntimeError('Expected the existing YomaTV MAL backend')
    patches = {}
    callback = htdocs / 'mal-callback.php'
    text = callback.read_text(encoding='utf-8-sig')
    hook = "require_once __DIR__.'/private/yomashi-mal.php';\nif(is_string($_GET['state']??null)&&str_starts_with($_GET['state'],'ys_')) ys_callback_page();\n"
    if 'ys_callback_page' not in text:
        anchor = "header('Referrer-Policy: no-referrer');\n"
        if text.count(anchor) != 1: raise RuntimeError('Review the MAL callback before installing')
        text = text.replace(anchor, anchor + hook)
    patches[callback] = text
    http = htdocs / 'private/mal-http.php'
    text = http.read_text(encoding='utf-8-sig')
    if "'manga-search'" not in text:
        anchor = "    'search' => 'https://api.myanimelist.net/v2/anime',"
        if text.count(anchor)!=1: raise RuntimeError('Review the MAL HTTP adapter before installing')
        text=text.replace(anchor,anchor+"\n    'manga-search' => 'https://api.myanimelist.net/v2/manga',")
        anchor="  if (preg_match('/^anime:"
        index=text.find(anchor)
        if index<0: raise RuntimeError('MAL endpoint guard missing')
        prefix="""  if (preg_match('/^manga:([1-9][0-9]{0,8})$/D', $endpoint, $match)) {
    if ($method !== 'GET') throw new LogicException('Invalid MAL method.');
    $allowed[$endpoint]='https://api.myanimelist.net/v2/manga/'.$match[1];
  } elseif (preg_match('/^manga-list-status:([1-9][0-9]{0,8})$/D', $endpoint, $match)) {
    if ($method !== 'PATCH') throw new LogicException('Invalid MAL method.');
    $allowed[$endpoint]='https://api.myanimelist.net/v2/manga/'.$match[1].'/my_list_status';
  } else"""
        text=text[:index]+prefix+text[index+2:]
    if "'manga-list'" not in text:
        anchor="'manga-search' => 'https://api.myanimelist.net/v2/manga',"
        if text.count(anchor)!=1: raise RuntimeError('Review the manga search route before adding the manga list')
        text=text.replace(anchor,anchor+"\n    'manga-list' => 'https://api.myanimelist.net/v2/users/@me/mangalist',")
    patches[http]=text
    publisher=web/'release.py'
    text=publisher.read_text(encoding='utf-8-sig')
    # Both the Python entry tuple and the PHP router's allowlist use this anchor.
    anchor="'app-manifest.php'"
    if "'yomashi-api.php'" not in text:
        if text.count(anchor)!=2: raise RuntimeError('Review the release entry allowlists')
        text=text.replace(anchor,anchor+",'yomashi-api.php','yomashi-connect.php'")
    patches[publisher]=text
    for source in (ROOT/'server').rglob('*.php'):
        patches[htdocs/source.relative_to(ROOT/'server')]=source.read_text(encoding='utf-8')
    # Validate every transformation before writing any of the existing files.
    for path,data in patches.items():
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(data,encoding='utf-8',newline='\n')
    print(f'Installed YomaShi extension: {len(patches)} files; credentials unchanged')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--web-root',type=Path,required=True)
    install(parser.parse_args().web_root.resolve())
