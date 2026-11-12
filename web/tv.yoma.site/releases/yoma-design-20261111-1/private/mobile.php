<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) { http_response_code(404); exit(); }

/** Installation-scoped data for the Android client; never returns MAL tokens. */
function dispatch_mobile(PDO $db, string $action, array $input): ?array
{
    if ($action === 'mobile_session') {
        return ['mobile_session' => ['user_id' => member(), 'csrf' => $_SESSION['csrf'], 'mal_account_id' => mal_identity_id($db)]];
    }
    if ($action !== 'offline_plan') return null;
    $user = member();
    $id = filter_var($input['episode_id'] ?? null, FILTER_VALIDATE_INT);
    if (!$id || $id < 1) throw new WebError('Capítulo inválido.');
    $episode = sql($db, 'SELECT id,slug FROM sa1_episodes WHERE id=?', [$id])->fetch();
    if (!$episode) throw new WebError('Capítulo no encontrado.', 404);
    $language = (string)($input['language'] ?? preferences($db, $user)['language']);
    if (!in_array($language, ['SUB','LAT','DUB'], true)) throw new WebError('Idioma inválido.');
    $anime = find_anime($db, $episode['slug']);
    $policy = watch_mode($db, $episode['slug']);
    $link = sql($db, 'SELECT k.confirmed,l.watched FROM sa1_mal_links k LEFT JOIN sa1_mal_list l ON l.user_id=k.user_id AND l.mal_id=k.mal_id WHERE k.user_id=? AND k.slug=?', [$user,$episode['slug']])->fetch();
    $rows = sql($db, 'SELECT e.id,e.number,w.watched_at FROM sa1_episodes e LEFT JOIN sa1_watched w ON w.episode_id=e.id AND w.user_id=? WHERE e.slug=? ORDER BY e.number_value,e.id', [$user,$episode['slug']])->fetchAll();
    $entries = [];
    episode_marks_apply($db,$rows);
    foreach ($rows as $index => $row) {
        $number = (float)$row['number'];
        $entries[] = ['episode_id'=>(int)$row['id'], 'number'=>(string)$row['number'],
            'watched'=>$row['watched_override']??((bool)$row['watched_at'] || ($link && $number >= 1 && floor($number) === $number && $number <= (int)($link['watched'] ?? 0))),
            'watched_override'=>$row['watched_override']??null,
            'next_episode_id'=>(int)($rows[$index+1]['id'] ?? 0)];
    }
    // Reading a download plan must not replace a playing device's session key.
    return ['offline_plan'=>['owner'=>$user,'title'=>$anime['title'],'slug'=>$episode['slug'],
        'cover'=>$anime['cover'] ?? '', 'season'=>$anime['season'] ?? '', 'language'=>$language,'mal_account_id'=>mal_identity_id($db),
        'mal_confirmed'=>(bool)($link['confirmed'] ?? false),'progress_revision'=>$policy['revision'],
        'episodes'=>$entries]];
}
