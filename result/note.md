初めて private isucon したのでその記録

## 初回ベンチ

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 3
2023/12/30 09:45:23 Start GET /initialize
2023/12/30 09:45:23 Benchmark Start!  Workload: 3
2023/12/30 09:46:28 Benchmark Finish!
2023/12/30 09:46:28 Score: 261
2023/12/30 09:46:28 Waiting for Stopping All Benchmarkers ...
```

- htop した限り mysql が CPU を使い果たしている
    - アプリケーションコードを見ながら DB ボトルネックを探す
    - 臭いクエリを EXPLAIN しつつクエリの改善を行う
    - まずはテーブルを見て index 有無を確認

```
mysql> show tables;
+--------------------+
| Tables_in_ishocon1 |
+--------------------+
| comments           |
| histories          |
| products           |
| users              |
+--------------------+
4 rows in set (0.00 sec)
```

```
+----------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table    | Create Table                                                                                                                                                                                                                                                                                            |
+----------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| comments | CREATE TABLE `comments` (
  `id` int NOT NULL AUTO_INCREMENT,
  `product_id` int NOT NULL,
  `user_id` int NOT NULL,
  `content` varchar(128) NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=200054 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci |
+----------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+

mysql> show create table histories;
+-----------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table     | Create Table                                                                                                                                                                                                                                                          |
+-----------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| histories | CREATE TABLE `histories` (
  `id` int NOT NULL AUTO_INCREMENT,
  `product_id` int NOT NULL,
  `user_id` int NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=500229 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci |
+-----------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+

mysql> show create table products;
+----------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table    | Create Table                                                                                                                                                                                                                                                                                                                   |
+----------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| products | CREATE TABLE `products` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `description` text,
  `image_path` varchar(32) NOT NULL,
  `price` int NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=10001 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci |
+----------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+

mysql> show create table users;
+-------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Table | Create Table                                                                                                                                                                                                                                                                                                 |
+-------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| users | CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(128) NOT NULL,
  `email` varchar(256) NOT NULL,
  `password` varchar(32) NOT NULL,
  `last_login` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=5001 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci |
+-------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.00 sec)
```


## index を貼っていく

- users 
    - (email)
- comments (product_id)
- histories (product_id, user_id)

```
ALTER TABLE users ADD INDEX idx_users_user_id (email);
ALTER TABLE comments ADD INDEX idx_comments_product_id (product_id, created_at);
ALTER TABLE histories ADD INDEX idx_histories_product_user (product_id, user_id);
```

```
ishocon@ip-172-16-10-156:~$ ./benchmark
2023/12/30 10:27:46 Start GET /initialize
2023/12/30 10:27:46 Benchmark Start!  Workload: 3
2023/12/30 10:28:46 Benchmark Finish!
2023/12/30 10:28:46 Score: 12546
2023/12/30 10:28:46 Waiting for Stopping All Benchmarkers ...
```

- index 付与がだいぶ効いた
- 一つ index が効いていない（using filesorts）なクエリがあったので index 追加

```
ALTER TABLE comments ADD INDEX idx_comments_product_id_created_at (product_id, created_at DESC);
```

```
ishocon@ip-172-16-10-156:~$ ./benchmark
2023/12/30 10:34:18 Start GET /initialize
2023/12/30 10:34:18 Benchmark Start!  Workload: 3
2023/12/30 10:35:18 Benchmark Finish!
2023/12/30 10:35:18 Score: 12489
2023/12/30 10:35:18 Waiting for Stopping All Benchmarkers ...
```

- あまり変わらず

## TODO
- images へのリクエストが多いので nginx などを入れて静的ファイルを返してあげる仕組みを入れると良さそうだが、やったことがないので後回し

# N+app code 改善

- UTC だったのを JST に変換する
    - 合わせて DB default value を変換
    - app code で timestamp 計算の必要がないので、insert は DB に任せて、update も CURRENT_TIMESTAMP を使用
```
ALTER TABLE comments MODIFY COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE histories MODIFY COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE products MODIFY COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
```

```
ishocon@ip-172-16-10-156:~$ ./benchmark
2023/12/30 10:51:46 Start GET /initialize
2023/12/30 10:51:46 Benchmark Start!  Workload: 3
2023/12/30 10:52:46 Benchmark Finish!
2023/12/30 10:52:46 Score: 12432
2023/12/30 10:52:46 Waiting for Stopping All Benchmarkers ...
```

- あまり効いてない :pieng:

## OFFSET が遅いはずなのでそれを直す

- products は抜け番なしの連番なので OFFSET を外せる

```
from;
products = db.xquery("SELECT * FROM products ORDER BY id DESC LIMIT 50 OFFSET #{}")

to;
last_id = page * 50
products = db.xquery("SELECT * FROM products where id < #{last_id} ORDER BY id DESC LIMIT 50}")
```

- あまり効かない

```
ishocon@ip-172-16-10-156:~$ ./benchmark
2023/12/30 10:58:17 Start GET /initialize
2023/12/30 10:58:17 Benchmark Start!  Workload: 3
2023/12/30 10:59:17 Benchmark Finish!
2023/12/30 10:59:17 Score: 12489
2023/12/30 10:59:17 Waiting for Stopping All Benchmarkers ...
```

# workload 調整
unicorn が 4 並列で動いているので、workload を 4 にする

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 11:00:48 Start GET /initialize
2023/12/30 11:00:48 Benchmark Start!  Workload: 4
2023/12/30 11:01:48 Benchmark Finish!
2023/12/30 11:01:48 Score: 16402
2023/12/30 11:01:48 Waiting for Stopping All Benchmarkers ...
```

# image の cache

```
set :static_cache_control, [:public, :max_age => 30000]
```

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 11:06:07 Start GET /initialize
2023/12/30 11:06:07 Benchmark Start!  Workload: 4
2023/12/30 11:07:07 Benchmark Finish!
2023/12/30 11:07:07 Score: 16506
2023/12/30 11:07:07 Waiting for Stopping All Benchmarkers ...
```

# さらに app code 改善

- current_user を都度 DB からとってるのがやばいからなんとかする
    - Sinatra よくわからないので、一旦複数とってるところは一回だけにする

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 11:14:00 Start GET /initialize
2023/12/30 11:14:00 Benchmark Start!  Workload: 4
2023/12/30 11:15:00 Benchmark Finish!
2023/12/30 11:15:00 Score: 16345
2023/12/30 11:15:00 Waiting for Stopping All Benchmarkers ...
```

- view で current_user にアクセスしないように

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 11:29:58 Start GET /initialize
2023/12/30 11:29:58 Benchmark Start!  Workload: 4
2023/12/30 11:30:58 Benchmark Finish!
2023/12/30 11:30:58 Score: 16350
2023/12/30 11:30:58 Waiting for Stopping All Benchmarkers ...
```

- current_user で id, name, email しか取らないように

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 11:39:17 Start GET /initialize
2023/12/30 11:39:17 Benchmark Start!  Workload: 4

2023/12/30 11:40:17 Benchmark Finish!
2023/12/30 11:40:17 Score: 16340
2023/12/30 11:40:17 Waiting for Stopping All Benchmarkers ...
```

- N+1 を解決したつもりだが、、、

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 11:58:29 Start GET /initialize
2023/12/30 11:58:29 Benchmark Start!  Workload: 4
2023/12/30 11:59:29 Benchmark Finish!
2023/12/30 11:59:29 Score: 15914
2023/12/30 11:59:29 Waiting for Stopping All Benchmarkers ...
```

---

## 重大なことに気づく

- 本来 ssh した先で app code を書き換えないといけないところ、ローカルのファイルのみを編集していた。
- ので、以上のうち、本当に聞いていたのは DB index だけ（bench の workload もあるが基本的に無視していい範囲）
	- 逆に言えば、DB index だけでここまではいける
- 以下は、そのことに気づいてからの note

---

- なんか壊したっぽいので、コードを戻した

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 14:09:45 Start GET /initialize
2023/12/30 14:09:45 Benchmark Start!  Workload: 4
2023/12/30 14:10:45 Benchmark Finish!
2023/12/30 14:10:45 Score: 15857
2023/12/30 14:10:45 Waiting for Stopping All Benchmarkers ...
```

- image の content cache

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 14:11:10 Start GET /initialize
2023/12/30 14:11:10 Benchmark Start!  Workload: 4
2023/12/30 14:12:10 Benchmark Finish!
2023/12/30 14:12:10 Score: 16179
2023/12/30 14:12:10 Waiting for Stopping All Benchmarkers ...
```

- current datetime の取得は DB に任せる

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 14:13:08 Start GET /initialize
2023/12/30 14:13:08 Benchmark Start!  Workload: 4
2023/12/30 14:14:08 Benchmark Finish!
2023/12/30 14:14:08 Score: 16293
2023/12/30 14:14:08 Waiting for Stopping All Benchmarkers ...
```

- current_user が都度 DB アクセスするのでなるべく使わない

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 14:23:53 Start GET /initialize
2023/12/30 14:23:53 Benchmark Start!  Workload: 4
2023/12/30 14:24:53 Benchmark Finish!
2023/12/30 14:24:53 Score: 16999
2023/12/30 14:24:53 Waiting for Stopping All Benchmarkers ...
```

- GET / の N+1 クエリ解消

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 14:42:32 Start GET /initialize
2023/12/30 14:42:32 Benchmark Start!  Workload: 4
2023/12/30 14:43:32 Benchmark Finish!
2023/12/30 14:43:32 Score: 14819
2023/12/30 14:43:32 Waiting for Stopping All Benchmarkers ...
```

- 遅くなったので、products を先に取ってそれ以外は IN 句でクエリすることに

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 15:24:50 Start GET /initialize
2023/12/30 15:24:50 Benchmark Start!  Workload: 4
2023/12/30 15:25:50 Benchmark Finish!
2023/12/30 15:25:50 Score: 17715
2023/12/30 15:25:50 Waiting for Stopping All Benchmarkers ...
```

- FK を貼る

以下をそれぞれ貼るも、特にスコア悪くなったが、誤差の範囲か
```
ALTER TABLE comments ADD CONSTRAINT fk_comments_to_users FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE histories ADD CONSTRAINT fk_histories_to_products FOREIGN KEY (product_id) REFERENCES products (id);
```

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 15:30:51 Start GET /initialize
2023/12/30 15:30:51 Benchmark Start!  Workload: 4
2023/12/30 15:31:52 Benchmark Finish!
2023/12/30 15:31:52 Score: 17549
2023/12/30 15:31:52 Waiting for Stopping All Benchmarkers ...
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 15:34:54 Start GET /initialize
2023/12/30 15:34:54 Benchmark Start!  Workload: 4
2023/12/30 15:35:54 Benchmark Finish!
2023/12/30 15:35:54 Score: 17658
2023/12/30 15:35:54 Waiting for Stopping All Benchmarkers ...
```

- pt-query-digest が使えなかったから slow query log 設定を OFF

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 15:38:53 Start GET /initialize
2023/12/30 15:38:53 Benchmark Start!  Workload: 4
2023/12/30 15:39:53 Benchmark Finish!
2023/12/30 15:39:53 Score: 17269
2023/12/30 15:39:53 Waiting for Stopping All Benchmarkers ...
```

- histories に ID 降順の index 付与

ALTER TABLE histories ADD INDEX idx_pk_desc (id DESC);
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 15:45:37 Start GET /initialize
2023/12/30 15:45:37 Benchmark Start!  Workload: 4
2023/12/30 15:46:37 Benchmark Finish!
2023/12/30 15:46:37 Score: 17601
2023/12/30 15:46:37 Waiting for Stopping All Benchmarkers ...
```

- unicorn のワーカ数を 4 から 8 に

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 15:50:39 Start GET /initialize
2023/12/30 15:50:39 Benchmark Start!  Workload: 4
2023/12/30 15:51:39 Benchmark Finish!
2023/12/30 15:51:39 Score: 18073
2023/12/30 15:51:39 Waiting for Stopping All Benchmarkers ...
```

- get '/products/:product_id' で使わないコメントを取得していたのを削除

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 15:54:58 Start GET /initialize
2023/12/30 15:54:58 Benchmark Start!  Workload: 4
2023/12/30 15:55:58 Benchmark Finish!
2023/12/30 15:55:58 Score: 18269
2023/12/30 15:55:58 Waiting for Stopping All Benchmarkers ...
```

- current_user で必要なカラムのみ取得

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 15:58:01 Start GET /initialize
2023/12/30 15:58:01 Benchmark Start!  Workload: 4
2023/12/30 15:59:01 Benchmark Finish!
2023/12/30 15:59:01 Score: 18130
2023/12/30 15:59:01 Waiting for Stopping All Benchmarkers ...
```

- 画像を webp に変換

ベンチに引っかかった
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 16:07:41 Start GET /initialize
2023/12/30 16:07:41 Benchmark Start!  Workload: 4
2023/12/30 16:07:41 Invalid Content or DOM at GET /index
2023/12/30 16:07:41 商品説明部分が正しくありません
```

- JPEG 画像を圧縮

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 16:12:06 Start GET /initialize
2023/12/30 16:12:06 Benchmark Start!  Workload: 4
2023/12/30 16:13:06 Benchmark Finish!
2023/12/30 16:13:06 Score: 18410
2023/12/30 16:13:06 Waiting for Stopping All Benchmarkers ...
```

- worker processs を 12 にしてみる

特に意味はなさそうなので戻す

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 16:35:45 Start GET /initialize
2023/12/30 16:35:45 Benchmark Start!  Workload: 4
2023/12/30 16:36:45 Benchmark Finish!
2023/12/30 16:36:45 Score: 17922
2023/12/30 16:36:45 Waiting for Stopping All Benchmarkers ...
```

- session 管理に redis 導入

あまり意味ない

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 16:40:37 Start GET /initialize
2023/12/30 16:40:37 Benchmark Start!  Workload: 4
2023/12/30 16:41:37 Benchmark Finish!
2023/12/30 16:41:37 Score: 18301
2023/12/30 16:41:37 Waiting for Stopping All Benchmarkers ...
```

- users のセッションに必要な情報を redis に載せる

```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 17:43:39 Start GET /initialize
2023/12/30 17:43:39 Benchmark Start!  Workload: 4
2023/12/30 17:44:39 Benchmark Finish!
2023/12/30 17:44:39 Score: 18078
2023/12/30 17:44:39 Waiting for Stopping All Benchmarkers ...
```

- マイページの購入履歴の index を改善

ALTER TABLE histories ADD INDEX idx_histories_user (user_id);
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 17:57:15 Start GET /initialize
2023/12/30 17:57:15 Benchmark Start!  Workload: 4
2023/12/30 17:58:15 Benchmark Finish!
2023/12/30 17:58:15 Score: 25818
2023/12/30 17:58:15 Waiting for Stopping All Benchmarkers ...
```

- CPU が空いたので worker を増やしてみる

あまり意味はないっぽい
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 18:00:50 Start GET /initialize
2023/12/30 18:00:50 Benchmark Start!  Workload: 4
2023/12/30 18:01:50 Benchmark Finish!
2023/12/30 18:01:50 Score: 25716
2023/12/30 18:01:50 Waiting for Stopping All Benchmarkers ...
```

- static cache control の max age を増やす

あまり意味はないっぽい
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 18:02:12 Start GET /initialize
2023/12/30 18:02:12 Benchmark Start!  Workload: 4
2023/12/30 18:03:12 Benchmark Finish!
2023/12/30 18:03:12 Score: 25119
2023/12/30 18:03:12 Waiting for Stopping All Benchmarkers ...
```

- workload を増やしてみる

むしろ悪化した
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 8
2023/12/30 18:03:19 Start GET /initialize
2023/12/30 18:03:19 Benchmark Start!  Workload: 8
2023/12/30 18:04:19 Benchmark Finish!
2023/12/30 18:04:19 Score: 22720
2023/12/30 18:04:19 Waiting for Stopping All Benchmarkers ...
```

12 も試す
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 12
2023/12/30 18:04:26 Start GET /initialize
2023/12/30 18:04:26 Benchmark Start!  Workload: 12
2023/12/30 18:05:26 Benchmark Finish!
2023/12/30 18:05:26 Score: 19528
2023/12/30 18:05:26 Waiting for Stopping All Benchmarkers ...
```

worker wお 16 にして workload を 8 にしてみる
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 8
2023/12/30 18:05:37 Start GET /initialize
2023/12/30 18:05:37 Benchmark Start!  Workload: 8
2023/12/30 18:06:37 Benchmark Finish!
2023/12/30 18:06:37 Score: 21983
2023/12/30 18:06:37 Waiting for Stopping All Benchmarkers ...
```

8 * 8
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 8
2023/12/30 18:07:02 Start GET /initialize
2023/12/30 18:07:02 Benchmark Start!  Workload: 8
2023/12/30 18:08:02 Benchmark Finish!
2023/12/30 18:08:02 Score: 21484
2023/12/30 18:08:02 Waiting for Stopping All Benchmarkers ...
```

8 * 4　が一番安定するっぽい
```
ishocon@ip-172-16-10-156:~$ ./benchmark --workload 4
2023/12/30 18:08:12 Start GET /initialize
2023/12/30 18:08:12 Benchmark Start!  Workload: 4
2023/12/30 18:09:12 Benchmark Finish!
2023/12/30 18:09:12 Score: 25804
2023/12/30 18:09:12 Waiting for Stopping All Benchmarkers ...
```

---

- 以上で8時間の期限切れ
- その後、nginx で静的ファイル配信までやったところ 58000 くらいまで出た
	- 不慣れゆえ、conf の書き方で苦戦しまくったので、やはり8時間の間ではできなかった

---

## まとめ

- DB index はちゃんと貼りましょう
- 計測もちゃんとしましょう
	- 今回は pt-query-digest がなぜか動かなかった（ハングした）
	- slow query log の閾値が低すぎてファイルがデカすぎたのかと思ったけど、たいしたサイズじゃなかったので、何か問題があるはずだが、深入りしなかった
	- いつかどこかで素振りしたい
- 今時はクラウドでロードバランサ・CDN でしょとか言わず、nginx 勉強しましょう
- 楽しいけど、誰だよこのクソコード書いたやつ、とかいった昔の悪夢を思い出すことになるので、用法・容量は正しく楽しんでやりましょう