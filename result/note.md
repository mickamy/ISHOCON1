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














