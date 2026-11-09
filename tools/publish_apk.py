"""Publish a verified personal APK to this repository's GitHub Releases.

Uses Git Credential Manager in memory. Never prints or stores access tokens.
Does not overwrite existing release assets or generate a different signing key.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPO = 'EduardoGPT4/YomaShi'
API = 'https://api.github.com/repos/' + REPO


class GitHubRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, url):
        parsed = urllib.parse.urlsplit(url)
        host = parsed.hostname or ''
        if parsed.scheme != 'https' or not (
            host in ('github.com', 'api.github.com', 'uploads.github.com')
            or host.endswith('.githubusercontent.com')
        ):
            raise RuntimeError('GitHub returned an unexpected download destination')
        result = super().redirect_request(req, fp, code, msg, headers, url)
        if result and parsed.netloc != urllib.parse.urlsplit(req.full_url).netloc:
            result.remove_header('Authorization')
            result.remove_header('Cookie')
        return result


class GitHub:
    def __init__(self):
        env = {**os.environ, 'GIT_TERMINAL_PROMPT': '0', 'GCM_INTERACTIVE': 'never'}
        result = subprocess.run(
            ['git', 'credential', 'fill'], cwd=ROOT,
            input='protocol=https\nhost=github.com\n\n',
            text=True, capture_output=True, env=env, timeout=60,
        )
        credential = dict(
            line.split('=', 1) for line in result.stdout.splitlines() if '=' in line
        )
        self.token = credential.get('password', '')
        if result.returncode or not self.token:
            raise RuntimeError('Authenticate GitHub with Git Credential Manager first')
        self.opener = urllib.request.build_opener(GitHubRedirects())

    def request(self, url, method='GET', payload=None, raw=None, accept='application/vnd.github+json'):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != 'https' or parsed.netloc not in ('api.github.com', 'uploads.github.com'):
            raise ValueError('Only GitHub release API endpoints are permitted')
        headers = {
            'Authorization': 'Bearer ' + self.token,
            'User-Agent': 'YomaShi-release-publisher',
            'X-GitHub-Api-Version': '2022-11-28', 'Accept': accept,
        }
        if payload is not None:
            raw = json.dumps(payload).encode()
            headers['Content-Type'] = 'application/json'
        elif raw is not None:
            headers['Content-Type'] = 'application/octet-stream'
        req = urllib.request.Request(url, data=raw, method=method, headers=headers)
        try:
            return self.opener.open(req, timeout=180)
        except urllib.error.HTTPError as error:
            # Do not echo headers, signed URLs, or credential-manager output.
            message = error.read(8192)
            try: detail = json.loads(message).get('message', 'GitHub rejected the request')
            except (ValueError, AttributeError): detail = 'GitHub rejected the request'
            raise ReleaseError(error.code, str(detail)) from None

    def json(self, url, **kwargs):
        with self.request(url, **kwargs) as response:
            return json.load(response)

    def verify(self, asset, content):
        digest = hashlib.sha256(content).hexdigest()
        if asset['size'] != len(content) or asset.get('state') != 'uploaded':
            raise RuntimeError('The uploaded asset is incomplete')
        advertised = asset.get('digest')
        if advertised:
            if advertised != 'sha256:' + digest:
                raise RuntimeError('The uploaded asset checksum does not match')
            return
        # Older API responses omit digest. Auth is stripped on CDN redirects.
        received = hashlib.sha256()
        size = 0
        with self.request(asset['url'], accept='application/octet-stream') as response:
            while block := response.read(1024 * 1024):
                received.update(block); size += len(block)
                if size > len(content): raise RuntimeError('Unexpected asset size')
        if size != len(content) or received.hexdigest() != digest:
            raise RuntimeError('Downloaded release asset differs from the local file')

    def existing_release(self, tag):
        # Authenticated listings include drafts, allowing interrupted uploads to resume.
        for page in range(1, 101):
            releases = self.json(API + f'/releases?per_page=100&page={page}')
            for release in releases:
                if release['tag_name'] == tag: return release
            if len(releases) < 100: return None
        raise RuntimeError('Too many releases to safely resolve the tag')

    def verify_target(self, tag, target, release):
        try: ref = self.json(API + '/git/ref/tags/' + tag)['object']
        except ReleaseError as error:
            if error.status != 404: raise
            if release and (not release['draft'] or release['target_commitish'] != target):
                raise RuntimeError('Existing release targets different source code')
            return
        for _ in range(16):
            if ref['type'] == 'commit':
                if ref['sha'] != target: raise RuntimeError('Existing tag targets a different commit; do not retag it')
                return
            if ref['type'] != 'tag': raise RuntimeError('Unexpected tag object type')
            ref = self.json(API + '/git/tags/' + ref['sha'])['object']
        raise RuntimeError('Unexpected nested Git tag')


class ReleaseError(RuntimeError):
    def __init__(self, status, message):
        self.status = status
        super().__init__(f'GitHub HTTP {status}: {message}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--notes-file', type=Path, required=True)
    parser.add_argument('--target', help='Exact Git commit used to build the APK; defaults to HEAD')
    args = parser.parse_args()
    version = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$',
                        (ROOT/'pubspec.yaml').read_text(), re.MULTILINE).group(1)
    if args.apk.name != f'YomaShi-{version}-arm64.apk':
        raise ValueError('Use the versioned personal ARM64 APK matching pubspec.yaml')
    content = args.apk.read_bytes()
    if not content.startswith(b'PK'):
        raise ValueError('The file is not an APK archive')
    target = subprocess.check_output(
        ['git', 'rev-parse', '--verify', (args.target or 'HEAD') + '^{commit}'],
        cwd=ROOT, text=True,
    ).strip()
    notes = args.notes_file.read_text(encoding='utf-8').strip()
    if not notes: raise ValueError('Provide release notes')
    github = GitHub()
    tag = 'v' + version
    release = github.existing_release(tag)
    github.verify_target(tag, target, release)
    if release is None:
        release = github.json(API + '/releases', method='POST', payload={
            'tag_name': tag, 'target_commitish': target, 'name': 'YomaShi ' + version,
            'body': notes, 'draft': True, 'prerelease': False,
        })
    upload = release['upload_url'].split('{', 1)[0]
    if urllib.parse.urlsplit(upload).netloc != 'uploads.github.com':
        raise RuntimeError('Unexpected GitHub upload endpoint')
    assets = {asset['name']: asset for asset in release['assets']}
    checksum = f'{hashlib.sha256(content).hexdigest()}  {args.apk.name}\n'.encode()
    for name, value in [(args.apk.name, content), ('SHA256SUMS.txt', checksum)]:
        asset = assets.get(name)
        if asset is None:
            asset = github.json(upload + '?' + urllib.parse.urlencode({'name': name}),
                                method='POST', raw=value)
        github.verify(asset, value)
    if release['draft']:
        release = github.json(release['url'], method='PATCH', payload={'draft': False, 'make_latest': 'true'})
    print(json.dumps({'release': release['html_url'],
                      'apk': f'https://github.com/{REPO}/releases/download/{tag}/{args.apk.name}',
                      'sha256': hashlib.sha256(content).hexdigest(), 'verified': True}))


if __name__ == '__main__':
    main()
