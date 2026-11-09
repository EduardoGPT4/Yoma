"""Read-only MAL configuration check; prints only booleans, never credentials."""
from pathlib import Path
import io,json,re,ssl,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parent/'Expedition-7'))
from deploy import InfinityFTP,credentials
try:
    config=credentials()
    if config['username']!='if0_43115975' or config['database']!='if0_43115975_anime':raise RuntimeError('Unexpected hosting account')
    with InfinityFTP(context=ssl.create_default_context(),timeout=45) as ftp:
        ftp.connect('ftpupload.net',21);ftp.login(config['username'],config['password']);ftp.prot_p()
        buffer=io.BytesIO();ftp.retrbinary('RETR /htdocs/seasonav1/private/config.local.php',buffer.write)
    text=buffer.getvalue().decode('utf-8-sig')
    def value(name):
        match=re.search(r"'"+re.escape(name)+r"'\s*=>\s*'([^']*)'",text)
        return match.group(1) if match else ''
    result={'client_id_matches_screenshot':value('client_id')=='4b2744af72ec84089ce310bf76b03dff',
            'redirect_matches_screenshot':value('redirect_uri')=='https://hk-br035.gt.tc/seasonav1/mal-callback.php',
            'server_secret_configured':bool(re.fullmatch('[a-f0-9]{64}',value('client_secret'))),
            'read_only':True,'credentials_saved_locally':False}
    (ROOT/'docs/yoma/mal-configuration-check.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result))
except Exception as error:
    print(json.dumps({'verification_failed':True,'error_type':type(error).__name__}));sys.exit(1)
