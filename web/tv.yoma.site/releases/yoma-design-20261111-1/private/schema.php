<?php
declare(strict_types=1);
if (!defined('SEASON_BOOTSTRAPPED')) {http_response_code(404);exit();}
function migrate_schema_legacy(PDO $db): void
{
  $mysql = $db->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql';
  $id = $mysql
    ? 'INTEGER PRIMARY KEY AUTO_INCREMENT'
    : 'INTEGER PRIMARY KEY AUTOINCREMENT';
  $tail = $mysql
    ? ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    : '';
  $tables = [
    'sa1_meta (name VARCHAR(100) PRIMARY KEY,value TEXT NOT NULL)',
    "sa1_users (id $id,name VARCHAR(60) NOT NULL,email VARCHAR(190) NOT NULL UNIQUE,password_hash VARCHAR(255) NOT NULL,created_at BIGINT NOT NULL)",
    'sa1_anime (slug VARCHAR(240) PRIMARY KEY,source_id INTEGER,title VARCHAR(400) NOT NULL,synopsis TEXT NOT NULL,cover VARCHAR(400) NOT NULL,weekday INTEGER NOT NULL,latest VARCHAR(16) NOT NULL,published VARCHAR(60) NOT NULL,start_date VARCHAR(30),season VARCHAR(40) NOT NULL,category VARCHAR(40) NOT NULL,active INTEGER NOT NULL DEFAULT 1,catalog_complete INTEGER NOT NULL DEFAULT 0,updated_at BIGINT NOT NULL)',
    "sa1_episodes (id $id,slug VARCHAR(240) NOT NULL,number VARCHAR(16) NOT NULL,number_value DOUBLE NOT NULL,url VARCHAR(500) NOT NULL,mirrors TEXT,mirrors_at BIGINT NOT NULL DEFAULT 0,UNIQUE(slug,number),FOREIGN KEY(slug) REFERENCES sa1_anime(slug))",
    "sa1_follow (user_id INTEGER NOT NULL,slug VARCHAR(240) NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'watching',favorite INTEGER NOT NULL DEFAULT 0,excluded INTEGER NOT NULL DEFAULT 0,score INTEGER NOT NULL DEFAULT 0,notes TEXT NOT NULL,PRIMARY KEY(user_id,slug),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(slug) REFERENCES sa1_anime(slug))",
    'sa1_watched (user_id INTEGER NOT NULL,episode_id INTEGER NOT NULL,watched_at BIGINT NOT NULL,PRIMARY KEY(user_id,episode_id),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(episode_id) REFERENCES sa1_episodes(id))',
    "sa1_jobs (id $id,user_id INTEGER NOT NULL,episode_id INTEGER NOT NULL,language VARCHAR(10) NOT NULL,server VARCHAR(20) NOT NULL,height INTEGER NOT NULL,status VARCHAR(20) NOT NULL DEFAULT 'pending',added_at BIGINT NOT NULL,exported_at BIGINT,confirmed_at BIGINT,bytes BIGINT,sha256 VARCHAR(64),UNIQUE(user_id,episode_id,language),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(episode_id) REFERENCES sa1_episodes(id))",
    'sa1_preferences (user_id INTEGER PRIMARY KEY,settings TEXT NOT NULL,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
    "sa1_history (id $id,user_id INTEGER NOT NULL,level VARCHAR(10) NOT NULL,message TEXT NOT NULL,created_at BIGINT NOT NULL,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)",
    'sa1_limits (name VARCHAR(190) PRIMARY KEY,hits INTEGER NOT NULL,reset_at BIGINT NOT NULL)',
    'sa1_recovery (user_id INTEGER NOT NULL,code_hash VARCHAR(64) NOT NULL,created_at BIGINT NOT NULL,used_at BIGINT,PRIMARY KEY(user_id,code_hash),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
    'sa1_mal_connections (user_id INTEGER PRIMARY KEY,mal_user_id BIGINT NOT NULL,mal_name VARCHAR(60) NOT NULL,token_cipher TEXT NOT NULL,expires_at BIGINT NOT NULL,connected_at BIGINT NOT NULL,checked_at BIGINT NOT NULL,needs_auth INTEGER NOT NULL DEFAULT 0,refresh_lock_until BIGINT NOT NULL DEFAULT 0,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
    'sa1_mal_identity (user_id INTEGER PRIMARY KEY,mal_user_id BIGINT NOT NULL,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
    'sa1_mal_removed (user_id INTEGER NOT NULL,mal_account_id BIGINT NOT NULL,mal_id INTEGER NOT NULL,removed_at BIGINT NOT NULL,PRIMARY KEY(user_id,mal_account_id,mal_id),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
    'sa1_mal_anime (mal_id INTEGER PRIMARY KEY,title VARCHAR(400) NOT NULL,aliases TEXT NOT NULL,search_key TEXT NOT NULL,cover VARCHAR(500) NOT NULL,media_type VARCHAR(30) NOT NULL,start_date VARCHAR(30) NOT NULL,airing_status VARCHAR(30) NOT NULL,num_episodes INTEGER NOT NULL,duration_seconds INTEGER NOT NULL,genres TEXT NOT NULL,updated_at BIGINT NOT NULL)',
    'sa1_mal_list (user_id INTEGER NOT NULL,mal_id INTEGER NOT NULL,status VARCHAR(30) NOT NULL,watched INTEGER NOT NULL,score INTEGER NOT NULL,notes TEXT NOT NULL,source VARCHAR(10) NOT NULL,sync_run VARCHAR(64) NOT NULL,updated_at BIGINT NOT NULL,PRIMARY KEY(user_id,mal_id),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(mal_id) REFERENCES sa1_mal_anime(mal_id))',
    'sa1_mal_links (user_id INTEGER NOT NULL,slug VARCHAR(240) NOT NULL,mal_id INTEGER NOT NULL,confirmed INTEGER NOT NULL,PRIMARY KEY(user_id,slug),UNIQUE(user_id,mal_id),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(slug) REFERENCES sa1_anime(slug),FOREIGN KEY(mal_id) REFERENCES sa1_mal_anime(mal_id))',
    'sa1_mal_sync (user_id INTEGER PRIMARY KEY,run_id VARCHAR(64) NOT NULL,next_offset INTEGER NOT NULL,updated_at BIGINT NOT NULL,finished_at BIGINT NOT NULL,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
    "sa1_notifications (id $id,user_id INTEGER NOT NULL,slug VARCHAR(240) NOT NULL,number VARCHAR(16) NOT NULL,created_at BIGINT NOT NULL,read_at BIGINT,UNIQUE(user_id,slug,number),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(slug) REFERENCES sa1_anime(slug))",
    'sa1_anime_search (slug VARCHAR(240) PRIMARY KEY,search_key TEXT NOT NULL,FOREIGN KEY(slug) REFERENCES sa1_anime(slug) ON DELETE CASCADE)',
    'sa1_catalog_mal (slug VARCHAR(240) PRIMARY KEY,mal_id INTEGER,extra TEXT NOT NULL,updated_at BIGINT NOT NULL,FOREIGN KEY(slug) REFERENCES sa1_anime(slug) ON DELETE CASCADE,FOREIGN KEY(mal_id) REFERENCES sa1_mal_anime(mal_id))',
    'sa1_catalog_source (slug VARCHAR(240) PRIMARY KEY,genres TEXT NOT NULL,premiere_year INTEGER,airing_status VARCHAR(30) NOT NULL,updated_at BIGINT NOT NULL,FOREIGN KEY(slug) REFERENCES sa1_anime(slug) ON DELETE CASCADE)',
    'sa1_episode_languages (episode_id INTEGER NOT NULL,language VARCHAR(10) NOT NULL,PRIMARY KEY(episode_id,language),FOREIGN KEY(episode_id) REFERENCES sa1_episodes(id) ON DELETE CASCADE)',
    'sa1_catalog_freshness (slug VARCHAR(240) PRIMARY KEY,episodes_at BIGINT NOT NULL DEFAULT 0,genres_at BIGINT NOT NULL DEFAULT 0,airing_at BIGINT NOT NULL DEFAULT 0,directory_at BIGINT NOT NULL DEFAULT 0,relations_at BIGINT NOT NULL DEFAULT 0,FOREIGN KEY(slug) REFERENCES sa1_anime(slug) ON DELETE CASCADE)',
    "sa1_catalog_tasks (task_key VARCHAR(64) PRIMARY KEY,kind VARCHAR(20) NOT NULL,target VARCHAR(260) NOT NULL,payload TEXT NOT NULL,state VARCHAR(20) NOT NULL,priority INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_retry BIGINT NOT NULL DEFAULT 0,lock_until BIGINT NOT NULL DEFAULT 0,error TEXT NOT NULL,created_at BIGINT NOT NULL,updated_at BIGINT NOT NULL)",
    "sa1_saved_filters (id $id,user_id INTEGER NOT NULL,name VARCHAR(60) NOT NULL,filters TEXT NOT NULL,updated_at BIGINT NOT NULL,UNIQUE(user_id,name),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)",
    'sa1_relations (slug VARCHAR(240) NOT NULL,target VARCHAR(240) NOT NULL,relation VARCHAR(30) NOT NULL,evidence VARCHAR(500) NOT NULL,state VARCHAR(20) NOT NULL,reviewed_by INTEGER,updated_at BIGINT NOT NULL,PRIMARY KEY(slug,target),FOREIGN KEY(slug) REFERENCES sa1_anime(slug) ON DELETE CASCADE,FOREIGN KEY(target) REFERENCES sa1_anime(slug) ON DELETE CASCADE)',
    'sa1_calendar_feeds (user_id INTEGER PRIMARY KEY,feed_key VARCHAR(64) NOT NULL,scope VARCHAR(20) NOT NULL,updated_at BIGINT NOT NULL,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
    'sa1_notice_baseline (slug VARCHAR(240) PRIMARY KEY,number_value DOUBLE NOT NULL,FOREIGN KEY(slug) REFERENCES sa1_anime(slug) ON DELETE CASCADE)',
    'sa1_watch_modes (user_id INTEGER NOT NULL,slug VARCHAR(240) NOT NULL,mode VARCHAR(10) NOT NULL,revision VARCHAR(32) NOT NULL,changed_at BIGINT NOT NULL DEFAULT 0,PRIMARY KEY(user_id,slug),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(slug) REFERENCES sa1_anime(slug) ON DELETE CASCADE)',
    'sa1_playback (user_id INTEGER NOT NULL,episode_id INTEGER NOT NULL,mode VARCHAR(10) NOT NULL,position DOUBLE NOT NULL DEFAULT 0,duration DOUBLE NOT NULL DEFAULT 0,session_key VARCHAR(32) NOT NULL,sequence_no BIGINT NOT NULL DEFAULT 0,updated_at BIGINT NOT NULL DEFAULT 0,PRIMARY KEY(user_id,episode_id,mode),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(episode_id) REFERENCES sa1_episodes(id) ON DELETE CASCADE)',
    'sa1_rewatched (user_id INTEGER NOT NULL,episode_id INTEGER NOT NULL,run_id VARCHAR(32) NOT NULL,watched_at BIGINT NOT NULL,PRIMARY KEY(user_id,episode_id,run_id),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(episode_id) REFERENCES sa1_episodes(id) ON DELETE CASCADE)',
    'sa1_player_preferences (user_id INTEGER PRIMARY KEY,settings TEXT NOT NULL,FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE)',
    'sa1_player_anime (user_id INTEGER NOT NULL,slug VARCHAR(240) NOT NULL,settings TEXT NOT NULL,PRIMARY KEY(user_id,slug),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(slug) REFERENCES sa1_anime(slug) ON DELETE CASCADE)',
    'sa1_job_runs (job_id INTEGER PRIMARY KEY,revision VARCHAR(32) NOT NULL,FOREIGN KEY(job_id) REFERENCES sa1_jobs(id) ON DELETE CASCADE)',
    'sa1_job_presence (user_id INTEGER NOT NULL,job_id INTEGER NOT NULL,device_id VARCHAR(64) NOT NULL,present INTEGER NOT NULL,checked_at BIGINT NOT NULL,PRIMARY KEY(user_id,job_id,device_id),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(job_id) REFERENCES sa1_jobs(id) ON DELETE CASCADE)',
    "sa1_watch_sync (user_id INTEGER NOT NULL,slug VARCHAR(240) NOT NULL,mal_id INTEGER NOT NULL DEFAULT 0,target INTEGER NOT NULL,generation VARCHAR(32) NOT NULL,state VARCHAR(20) NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,next_retry BIGINT NOT NULL DEFAULT 0,lock_until BIGINT NOT NULL DEFAULT 0,error_kind VARCHAR(30) NOT NULL DEFAULT '',updated_at BIGINT NOT NULL,PRIMARY KEY(user_id,slug),FOREIGN KEY(user_id) REFERENCES sa1_users(id) ON DELETE CASCADE,FOREIGN KEY(slug) REFERENCES sa1_anime(slug))",
  ];
  foreach ($tables as $table) {
    $db->exec('CREATE TABLE IF NOT EXISTS ' . $table . $tail);
  }
  if (meta($db, 'reliability_schema') !== '1') {
    $columns = $mysql ? $db->query('SHOW COLUMNS FROM sa1_watch_sync')->fetchAll()
      : $db->query('PRAGMA table_info(sa1_watch_sync)')->fetchAll();
    if (!in_array('mal_account_id', array_column($columns, $mysql ? 'Field' : 'name'), true)) {
      try { $db->exec('ALTER TABLE sa1_watch_sync ADD COLUMN mal_account_id BIGINT NOT NULL DEFAULT 0'); }
      catch (PDOException $error) {
        $columns = $mysql ? $db->query('SHOW COLUMNS FROM sa1_watch_sync')->fetchAll()
          : $db->query('PRAGMA table_info(sa1_watch_sync)')->fetchAll();
        if (!in_array('mal_account_id', array_column($columns, $mysql ? 'Field' : 'name'), true)) throw $error;
      }
    }
    foreach (sql($db, 'SELECT user_id,mal_user_id FROM sa1_mal_connections')->fetchAll() as $owner) {
      upsert($db, 'sa1_mal_identity', ['user_id','mal_user_id'], [$owner], ['user_id'], ['mal_user_id']);
      sql($db, 'UPDATE sa1_watch_sync SET mal_account_id=? WHERE user_id=? AND mal_account_id=0',
        [$owner['mal_user_id'], $owner['user_id']]);
    }
    foreach (sql($db, 'SELECT id FROM sa1_users u WHERE NOT EXISTS(SELECT 1 FROM sa1_mal_identity i WHERE i.user_id=u.id) AND (EXISTS(SELECT 1 FROM sa1_mal_list l WHERE l.user_id=u.id) OR EXISTS(SELECT 1 FROM sa1_mal_links k WHERE k.user_id=u.id) OR EXISTS(SELECT 1 FROM sa1_watch_sync w WHERE w.user_id=u.id))')->fetchAll() as $unknown)
      upsert($db,'sa1_mal_identity',['user_id','mal_user_id'],[['user_id'=>$unknown['id'],'mal_user_id'=>0]],['user_id'],['mal_user_id']);
    // A legacy disconnected outbox has no provable MAL owner. Preserve local marks,
    // but never silently attribute those old sends to the next account connected.
    sql($db, "UPDATE sa1_watch_sync SET state='blocked',error_kind='identity_unknown' WHERE mal_account_id=0 AND NOT EXISTS(SELECT 1 FROM sa1_mal_connections c WHERE c.user_id=sa1_watch_sync.user_id)");
    set_meta($db, 'reliability_schema', '1');
  }
  if (meta($db, 'security_schema') !== '1') {
    $columns = $mysql
      ? $db->query('SHOW COLUMNS FROM sa1_users')->fetchAll()
      : $db->query('PRAGMA table_info(sa1_users)')->fetchAll();
    if (
      !in_array(
        'auth_version',
        array_column($columns, $mysql ? 'Field' : 'name'),
        true,
      )
    ) {
      try {
        $db->exec(
          'ALTER TABLE sa1_users ADD COLUMN auth_version INTEGER NOT NULL DEFAULT 0',
        );
      } catch (PDOException $error) {
        $columns = $mysql
          ? $db->query('SHOW COLUMNS FROM sa1_users')->fetchAll()
          : $db->query('PRAGMA table_info(sa1_users)')->fetchAll();
        if (
          !in_array(
            'auth_version',
            array_column($columns, $mysql ? 'Field' : 'name'),
            true,
          )
        ) {
          throw $error;
        }
      }
    }
    set_meta($db, 'security_schema', '1');
  }
}
function seed_data(PDO $db): void
{
  if (!meta($db, 'installation')) {
    set_meta($db, 'installation', bin2hex(random_bytes(16)));
  }
  if (!meta($db, 'seeded')) {
    $seed = json_decode(
      file_get_contents(dirname(__DIR__) . '/data/season.json'),
      true,
      512,
      JSON_THROW_ON_ERROR,
    );
    $db->beginTransaction();
    try {
      upsert(
        $db,
        'sa1_anime',
        array_keys($seed['anime'][0]),
        $seed['anime'],
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
          'catalog_complete',
          'updated_at',
        ],
      );
      upsert(
        $db,
        'sa1_episodes',
        ['slug', 'number', 'number_value', 'url'],
        $seed['episodes'],
        ['slug', 'number'],
        ['url'],
      );
      set_meta($db, 'catalog_updated', (string) $seed['fetched_at']);
      set_meta($db, 'seeded', '1');
      $db->commit();
    } catch (Throwable $e) {
      $db->rollBack();
      throw $e;
    }
  }
  $catalogFile = dirname(__DIR__) . '/data/catalog.json.gz';
  if (is_file($catalogFile)) {
    $catalogMeta = json_decode(
      file_get_contents(dirname(__DIR__) . '/data/catalog-meta.json'),
      true,
      512,
      JSON_THROW_ON_ERROR,
    );
    if (meta($db, 'directory_version') !== $catalogMeta['version']) {
      $catalog = json_decode(
        gzdecode(file_get_contents($catalogFile)),
        true,
        512,
        JSON_THROW_ON_ERROR,
      );
      if ($catalog['version'] !== $catalogMeta['version']) {
        throw new RuntimeException('El índice del catálogo está incompleto.');
      }
      $db->beginTransaction();
      try {
        upsert(
          $db,
          'sa1_anime',
          array_keys($catalog['anime'][0]),
          $catalog['anime'],
          ['slug'],
          ['source_id', 'title', 'synopsis', 'cover', 'category'],
        );
        set_meta($db, 'directory_version', $catalog['version']);
        set_meta($db, 'directory_updated', (string) $catalog['fetched_at']);
        set_meta(
          $db,
          'directory_source_total',
          (string) $catalog['source_total'],
        );
        $db->commit();
      } catch (Throwable $error) {
        $db->rollBack();
        throw $error;
      }
    }
  }
  unset($catalog, $seed);
  seed_catalog_source($db);
}
