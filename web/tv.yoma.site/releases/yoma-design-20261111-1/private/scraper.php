<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {
  http_response_code(404);
  exit();
}
final class ScraperError extends RuntimeException {}

final class LiteralReader
{
  private int $i = 0;
  public function __construct(private string $text) {}
  private function ws(): void
  {
    while (isset($this->text[$this->i]) && ctype_space($this->text[$this->i])) {
      $this->i++;
    }
  }
  private function string(): string
  {
    $q = $this->text[$this->i++];
    $out = '';
    while (isset($this->text[$this->i])) {
      $c = $this->text[$this->i++];
      if ($c === $q) {
        return $out;
      }
      if ($c !== '\\') {
        $out .= $c;
        continue;
      }
      if (!isset($this->text[$this->i])) {
        break;
      }
      $e = $this->text[$this->i++];
      $esc = [
        'n' => "\n",
        'r' => "\r",
        't' => "\t",
        'b' => "\x08",
        'f' => "\x0c",
        'v' => "\x0b",
        '0' => "\0",
      ];
      if ($e === 'u') {
        $hex = substr($this->text, $this->i, 4);
        $this->i += 4;
        if (!ctype_xdigit($hex) || strlen($hex) !== 4) {
          throw new ScraperError('Escape inválido.');
        }
        $raw = '\\u' . $hex;
        if (
          hexdec($hex) >= 0xd800 &&
          hexdec($hex) <= 0xdbff &&
          substr($this->text, $this->i, 2) === '\\u'
        ) {
          $raw .= substr($this->text, $this->i, 6);
          $this->i += 6;
        }
        $out .= json_decode('"' . $raw . '"', true, 512, JSON_THROW_ON_ERROR);
      } elseif ($e === 'x') {
        $hex = substr($this->text, $this->i, 2);
        $this->i += 2;
        if (strlen($hex) !== 2 || !ctype_xdigit($hex)) {
          throw new ScraperError('Escape inválido.');
        }
        $out .= mb_chr(hexdec($hex), 'UTF-8');
      } else {
        $out .= $esc[$e] ?? $e;
      }
    }
    throw new ScraperError('Cadena incompleta.');
  }
  public function value(int $depth = 0): mixed
  {
    if ($depth > 40) {
      throw new ScraperError('Datos demasiado anidados.');
    }
    $this->ws();
    $c = $this->text[$this->i] ?? '';
    if ($c === '"' || $c === "'") {
      return $this->string();
    }
    if ($c === '[' || $c === '{') {
      $this->i++;
      $out = [];
      $object = $c === '{';
      $end = $object ? '}' : ']';
      $this->ws();
      while (($this->text[$this->i] ?? '') !== $end) {
        if ($object) {
          $this->ws();
          $first = $this->text[$this->i] ?? '';
          if ($first === '"' || $first === "'") {
            $key = $this->string();
          } elseif (
            preg_match('/\G[A-Za-z_$][\w$]*/A', $this->text, $m, 0, $this->i)
          ) {
            $key = $m[0];
            $this->i += strlen($key);
          } else {
            throw new ScraperError('Clave inesperada.');
          }
          $this->ws();
          if (($this->text[$this->i++] ?? '') !== ':') {
            throw new ScraperError('Falta separador.');
          }
          $out[$key] = $this->value($depth + 1);
        } else {
          $out[] = $this->value($depth + 1);
        }
        $this->ws();
        $next = $this->text[$this->i] ?? '';
        if ($next === $end) {
          break;
        }
        if ($next !== ',') {
          throw new ScraperError('Literal inesperado.');
        }
        $this->i++;
        $this->ws();
      }
      $this->i++;
      return $out;
    }
    if (
      preg_match('/\G(?:true|false|null)\b/A', $this->text, $m, 0, $this->i)
    ) {
      $this->i += strlen($m[0]);
      return json_decode($m[0]);
    }
    if (
      preg_match(
        '/\G-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/A',
        $this->text,
        $m,
        0,
        $this->i,
      )
    ) {
      $this->i += strlen($m[0]);
      return 0 + $m[0];
    }
    throw new ScraperError('La página contiene datos que no son literales.');
  }
  public static function property(string $source, string $name): mixed
  {
    preg_match_all(
      '/"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\'|[A-Za-z_$][\w$]*/s',
      $source,
      $tokens,
      PREG_OFFSET_CAPTURE,
    );
    foreach ($tokens[0] as [$token, $offset]) {
      if (
        !in_array($token, [$name, '"' . $name . '"', "'" . $name . "'"], true)
      ) {
        continue;
      }
      $end = $offset + strlen($token);
      if (preg_match('/\G\s*:\s*/A', $source, $match, 0, $end)) {
        return new self(substr($source, $end + strlen($match[0])))->value();
      }
    }
    return null;
  }
}

function reserve_scraper_budget(PDO $db,int $user,bool $interactive): void
{
  $own=!$db->inTransaction();if($own)$db->beginTransaction();
  try{
    // A denied spacing check does not spend an hourly request that never reaches the origin.
    rate($db,'scraper-spacing',1,2);
    if(!$interactive)rate($db,'scraper-maintenance',90,3600);
    rate($db,'scraper-user:'.$user,120,3600);rate($db,'scraper-global',120,3600);
    if($own)$db->commit();
  }catch(Throwable $error){if($own&&$db->inTransaction())$db->rollBack();throw $error;}
}
function public_html(string $path): string
{
  $task=$GLOBALS['season_scrape_task']??null;
  $trusted=is_array($task)&&hash_equals($task['path'],$path);
  $user = $trusted ? 0 :
    (defined('SEASON_SYSTEM_REFRESH') && SEASON_SYSTEM_REFRESH
      ? 0
      : admin_member(db()));
  $interactive=(bool)($GLOBALS['season_scrape_interactive']??false)||($trusted&&$task['interactive']);
  if (
    !preg_match(
      '~^/(?:horario|catalogo\?(?:minYear=(?:19|20|21)\d{2}&maxYear=(?:19|20|21)\d{2}&)?page=[1-9]\d{0,3}|media/[A-Za-z0-9_-]+(?:/\d+(?:\.\d+)?)?)$~',
      $path,
    )
  ) {
    throw new ScraperError('Dirección de origen inválida.');
  }
  reserve_scraper_budget(db(),$user,$interactive);
  $curl = curl_init('https://animeav1.com' . $path);
  $body = '';
  curl_setopt_array($curl, [
    CURLOPT_CONNECTTIMEOUT => 4,
    CURLOPT_TIMEOUT => 10,
    CURLOPT_FOLLOWLOCATION => false,
    CURLOPT_ENCODING => '',
    CURLOPT_USERAGENT => 'YomaTVWeb/1.0 (public HTML)',
    CURLOPT_HTTPHEADER => ['Accept: text/html'],
    CURLOPT_WRITEFUNCTION => function ($c, $chunk) use (&$body) {
      if (strlen($body) + strlen($chunk) > 8 * 1024 * 1024) {
        return 0;
      }
      $body .= $chunk;
      return strlen($chunk);
    },
  ]);
  if(function_exists('release_remote_session'))release_remote_session();
  $ok = curl_exec($curl);
  $status = curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
  curl_close($curl);
  if (!$ok || $status !== 200) {
    throw new ScraperError(
      'No se pudo leer AnimeAV1. Se conserva el catálogo anterior; intenta de nuevo más tarde.',
    );
  }
  return $body;
}
function svelte_state(string $html): string
{
  preg_match_all('~<script\b[^>]*>(.*?)</script>~is', $html, $scripts);
  foreach ($scripts[1] as $s) {
    if (str_contains($s, 'kit.start(') && str_contains($s, 'data:')) {
      return $s;
    }
  }
  throw new ScraperError(
    'AnimeAV1 cambió su estructura o está pidiendo una verificación. Se conservaron tus datos.',
  );
}
function episode_number(mixed $n): string
{
  $v = (string) $n;
  if (!preg_match('/^\d{1,5}(?:\.\d{1,4})?$/', $v)) {
    throw new ScraperError('Número de capítulo inválido.');
  }
  [$w, $f] = array_pad(explode('.', $v, 2), 2, '');
  $w = (string) (int) $w;
  $f = rtrim($f, '0');
  return $w . ($f !== '' ? '.' . $f : '');
}
function season_name(?string $date = null): string
{
  $d = new DateTimeImmutable(
    $date ?? 'now',
    new DateTimeZone('America/Mexico_City'),
  );
  return ['invierno', 'primavera', 'verano', 'otoño'][
    intdiv((int) $d->format('n') - 1, 3)
  ] . $d->format('Y');
}
function sync_schedule(PDO $db): int
{
  $previous = [];
  foreach (
    sql($db, 'SELECT slug,latest FROM sa1_anime')->fetchAll()
    as $entry
  ) {
    $previous[$entry['slug']] = $entry['latest'];
  }
  $media = LiteralReader::property(
    svelte_state(public_html('/horario')),
    'media',
  );
  if (!is_array($media) || !$media) {
    throw new ScraperError(
      'El horario cambió de formato. No se modificó tu biblioteca.',
    );
  }
  $rows = [];
  $episodes = [];
  foreach ($media as $a) {
    if (!isset($a['latestEpisode'])) {
      continue;
    }
    if (
      !preg_match('/^[A-Za-z0-9_-]{1,240}$/', $a['slug'] ?? '') ||
      empty($a['title']) ||
      empty($a['latestEpisode']['createdAt'])
    ) {
      throw new ScraperError(
        'Una entrada del horario no tiene el formato esperado.',
      );
    }
    $moment = new DateTimeImmutable(
      $a['latestEpisode']['createdAt'],
    )->setTimezone(new DateTimeZone('America/Mexico_City'));
    $n = episode_number($a['latestEpisode']['number']);
    $slug = $a['slug'];
    $rows[] = [
      'slug' => $slug,
      'source_id' => (int) $a['id'],
      'title' => html_entity_decode(
        $a['title'],
        ENT_QUOTES | ENT_HTML5,
        'UTF-8',
      ),
      'synopsis' => html_entity_decode(
        $a['synopsis'] ?? '',
        ENT_QUOTES | ENT_HTML5,
        'UTF-8',
      ),
      'cover' => 'https://cdn.animeav1.com/covers/' . (int) $a['id'] . '.jpg',
      'weekday' => (int) $moment->format('N'),
      'latest' => $n,
      'published' => $moment->format(DATE_ATOM),
      'start_date' => $a['startDate'] ?? null,
      'season' => season_name($a['startDate'] ?? null),
      'category' => $a['category']['name'] ?? 'Anime',
      'active' => 1,
      'catalog_complete' => 0,
      'updated_at' => time(),
    ];
    $episodes[] = [
      'slug' => $slug,
      'number' => $n,
      'number_value' => (float) $n,
      'url' => 'https://animeav1.com/media/' . $slug . '/' . $n,
    ];
  }
  if (!$rows) {
    throw new ScraperError('El horario no contiene animes utilizables.');
  }
  $db->beginTransaction();
  try {
    $db->exec('UPDATE sa1_anime SET active=0');
    upsert(
      $db,
      'sa1_anime',
      array_keys($rows[0]),
      $rows,
      ['slug'],
      [
        'title',
        'synopsis',
        'cover',
        'weekday',
        'latest',
        'published',
        'start_date',
        'season',
        'category',
        'active',
        'updated_at',
      ],
    );
    upsert(
      $db,
      'sa1_episodes',
      array_keys($episodes[0]),
      $episodes,
      ['slug', 'number'],
      ['url'],
    );
    catalog_invalidate($db);
    set_meta($db, 'catalog_updated', (string) time());
    $db->commit();
  } catch (Throwable $e) {
    $db->rollBack();
    throw $e;
  }
  foreach ($rows as $row) {
    if (
      !empty($previous[$row['slug']]) &&
      (float) $row['latest'] > (float) $previous[$row['slug']]
    ) {
      $baseline = sql($db,'SELECT number_value FROM sa1_notice_baseline WHERE slug=?',[$row['slug']])->fetchColumn();
      $mark = ['slug'=>$row['slug'],'number_value'=>$baseline===false?(float)$previous[$row['slug']]:min((float)$baseline,(float)$previous[$row['slug']])];
      upsert($db,'sa1_notice_baseline',array_keys($mark),[$mark],['slug'],['number_value']);
      notify_new_episode($db, $row['slug'], $row['latest']);
    }
  }
  set_meta($db, 'scraper_error', '');
  sql($db,'UPDATE sa1_calendar_feeds SET updated_at=0');
  calendar_refresh_feeds($db);
  return count($rows);
}
function sync_anime(PDO $db, string $slug): int
{
  $oldLatest =
    (string) (sql($db, 'SELECT latest FROM sa1_anime WHERE slug=?', [
      $slug,
    ])->fetchColumn() ?:
    '');
  $html = public_html('/media/' . $slug);
  $state = svelte_state($html);
  $numbers = [];
  foreach (LiteralReader::property($state, 'episodes') ?? [] as $ep) {
    if (isset($ep['number'])) {
      $numbers[episode_number($ep['number'])] = true;
    }
  }
  preg_match_all(
    '~href=["\'](?:https://animeav1\.com)?/media/' .
      preg_quote($slug, '~') .
      '/(\d+(?:\.\d+)?)/?["\']~',
    $html,
    $matches,
  );
  foreach ($matches[1] as $number) {
    $numbers[episode_number($number)] = true;
  }
  if (!$numbers && LiteralReader::property($state, 'episodes') === null) {
    throw new ScraperError(
      'No se pudo leer el listado de capítulos. Se conserva el listado anterior.',
    );
  }
  $rows = [];
  foreach (array_keys($numbers) as $n) {
    $n = (string) $n;
    $rows[] = [
      'slug' => $slug,
      'number' => $n,
      'number_value' => (float) $n,
      'url' => 'https://animeav1.com/media/' . $slug . '/' . $n,
    ];
  }
  upsert(
    $db,
    'sa1_episodes',
    ['slug', 'number', 'number_value', 'url'],
    $rows,
    ['slug', 'number'],
    ['url'],
  );
  // Never take a related title's premiere when this title lacks its own date.
  $media = null;
  try { $media = LiteralReader::property($state,'media'); } catch (ScraperError $error) {}
  $start = is_array($media) && ($media['slug']??'')===$slug ? ($media['startDate']??null) : null;
  try { catalog_source_detail($db, $slug, $state); }
  catch (ScraperError $error) { /* Preserve the complete source snapshot if JS references prevent a safe parse. */ }
  if (!is_string($start) || !preg_match('/^\d{4}-\d{2}-\d{2}/', $start)) {
    $start = null;
  }
  $latest = $numbers
    ? (string) max(array_map('floatval', array_keys($numbers)))
    : '';
  sql(
    $db,
    'UPDATE sa1_anime SET catalog_complete=1,latest=?,start_date=COALESCE(?,start_date),season=CASE WHEN ? IS NULL THEN season ELSE ? END,updated_at=? WHERE slug=?',
    [$latest, $start, $start, $start ? season_name($start) : '', time(), $slug],
  );
  catalog_touch($db,$slug,['episodes_at']);
  try { catalog_relations_import($db,$slug,$html,$state); } catch (ScraperError $error) {}
  notify_episode_gap($db,$slug,$oldLatest,array_keys($numbers));
  return count($rows);
}
function sync_directory_page(PDO $db, int $page): array
{
  return sync_directory_html($db,public_html('/catalogo?page='.$page),$page);
}
function sync_directory_partition(PDO $db, int $low, int $high, int $page): array
{
  if ($low<1900 || $high>2199 || $low>$high || $page<1 || $page>9999) throw new ScraperError('Partición inválida.');
  $html=public_html("/catalogo?minYear=$low&maxYear=$high&page=$page");
  $filters=LiteralReader::property(svelte_state($html),'filters');
  if (($filters['years']??null)!==[$low,$high]) throw new ScraperError('El origen no respetó el filtro de años. Se conserva el cursor anterior.');
  return sync_directory_html($db,$html,$page);
}
function sync_directory_html(PDO $db, string $html, int $page): array
{
  $state = svelte_state($html);
  $categories = [];
  preg_match_all(
    '/(\w+)\.id=\d+;\w+\.name="([^"]+)";/',
    $state,
    $matches,
    PREG_SET_ORDER,
  );
  foreach ($matches as $m) {
    $categories[$m[1]] = $m[2];
  }
  $normalized = preg_replace_callback(
    '/\bcategory:([A-Za-z_$][\w$]*)\b/',
    fn($m) => 'category:' .
      json_encode(['name' => $categories[$m[1]] ?? 'Anime']),
    $state,
  );
  $entries = LiteralReader::property($normalized, 'results');
  $pagination = LiteralReader::property($state, 'pagination');
  if (
    !is_array($entries) ||
    !is_array($pagination) ||
    (int) ($pagination['currentPage'] ?? 0) !== $page ||
    (!is_array($entries) || (!$entries && (int)($pagination['totalRecords']??0)!==0))
  ) {
    throw new ScraperError(
      'El directorio cambió de formato. Se conserva el catálogo anterior.',
    );
  }
  if ((int)($pagination['totalRecords']??-1)<0 || (int)($pagination['totalPages']??-1)<0 ||
      (int)$pagination['totalPages']>9999 || (int)$pagination['totalRecords']>1000000)
    throw new ScraperError('Paginación del origen inválida.');
  $rows = [];
  foreach ($entries as $a) {
    if (
      !preg_match('/^[A-Za-z0-9_-]{1,240}$/', $a['slug'] ?? '') ||
      empty($a['title']) ||
      !is_numeric($a['id'] ?? null)
    ) {
      throw new ScraperError('Entrada de catálogo inválida.');
    }
    $rows[] = [
      'slug' => $a['slug'],
      'source_id' => (int) $a['id'],
      'title' => html_entity_decode(
        $a['title'],
        ENT_QUOTES | ENT_HTML5,
        'UTF-8',
      ),
      'synopsis' => html_entity_decode(
        $a['synopsis'] ?? '',
        ENT_QUOTES | ENT_HTML5,
        'UTF-8',
      ),
      'cover' => 'https://cdn.animeav1.com/covers/' . (int) $a['id'] . '.jpg',
      'weekday' => 0,
      'latest' => '',
      'published' => '',
      'start_date' => null,
      'season' => '',
      'category' => $a['category']['name'] ?? 'Anime',
      'active' => 0,
      'catalog_complete' => 0,
      'updated_at' => time(),
    ];
  }
  $db->beginTransaction();
  try {
    upsert(
      $db,
      'sa1_anime',
      $rows ? array_keys($rows[0]) : [],
      $rows,
      ['slug'],
      ['source_id', 'title', 'synopsis', 'cover', 'category'],
    );
    foreach ($rows as $row) catalog_touch($db,$row['slug'],['directory_at']);
    set_meta($db, 'directory_updated', (string) time());
    set_meta(
      $db,
      'directory_source_total',
      (string) $pagination['totalRecords'],
    );
    $db->commit();
  } catch (Throwable $error) {
    $db->rollBack();
    throw $error;
  }
  return [
    'page' => $page,
    'pages' => (int) $pagination['totalPages'],
    'count' => count($rows),
    'total' => (int) $pagination['totalRecords'],
  ];
}
function episode_mirrors(PDO $db, array $episode): array
{
  if ((int) $episode['mirrors_at'] > time() - 1800) {
    return json_decode($episode['mirrors'] ?? '[]', true) ?? [];
  }
  $state = svelte_state(
    public_html('/media/' . $episode['slug'] . '/' . $episode['number']),
  );
  $out = [];
  foreach (
    LiteralReader::property($state, 'embeds') ?? []
    as $language => $entries
  ) {
    foreach ($entries as $m) {
      $url = $m['url'] ?? '';
      $parts = parse_url($url);
      if (
        !in_array($m['server'] ?? '', ['MP4Upload', 'Voe'], true) ||
        ($parts['scheme'] ?? '') !== 'https' ||
        isset($parts['user']) ||
        empty($parts['host'])
      ) {
        continue;
      }
      $out[] = [
        'server' => $m['server'],
        'language' => strtoupper((string) $language),
        'url' => $url,
      ];
    }
  }
  sql($db, 'UPDATE sa1_episodes SET mirrors=?,mirrors_at=? WHERE id=?', [
    json_encode($out, JSON_UNESCAPED_SLASHES),
    time(),
    $episode['id'],
  ]);
  catalog_invalidate($db);
  catalog_index_languages($db, (int)$episode['id'], $out);
  return $out;
}
