require 'sinatra/base'
require 'mysql2'
require 'mysql2-cs-bind'
require 'erubis'

module Ishocon1
  class AuthenticationError < StandardError; end
  class PermissionDenied < StandardError; end
end

class Ishocon1::WebApp < Sinatra::Base
  session_secret = ENV['ISHOCON1_SESSION_SECRET'] || 'showwin_happy'
  use Rack::Session::Cookie, key: 'rack.session', secret: session_secret
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../public', __FILE__)
  set :protection, true
  set :static_cache_control, [:public, :max_age => 30000]

  helpers do
    def config
      @config ||= {
        db: {
          host: ENV['ISHOCON1_DB_HOST'] || 'localhost',
          port: ENV['ISHOCON1_DB_PORT'] && ENV['ISHOCON1_DB_PORT'].to_i,
          username: ENV['ISHOCON1_DB_USER'] || 'ishocon',
          password: ENV['ISHOCON1_DB_PASSWORD'] || 'ishocon',
          database: ENV['ISHOCON1_DB_NAME'] || 'ishocon1'
        }
      }
    end

    def db
      return Thread.current[:ishocon1_db] if Thread.current[:ishocon1_db]
      client = Mysql2::Client.new(
        host: config[:db][:host],
        port: config[:db][:port],
        username: config[:db][:username],
        password: config[:db][:password],
        database: config[:db][:database],
        reconnect: true
      )
      client.query_options.merge!(symbolize_keys: true)
      Thread.current[:ishocon1_db] = client
      client
    end

    def authenticate(email, password)
      user = db.xquery('SELECT * FROM users WHERE email = ?', email).first
      fail Ishocon1::AuthenticationError unless user.nil? == false && user[:password] == password
      session[:user_id] = user[:id]
    end

    def authenticated!
      fail Ishocon1::PermissionDenied unless current_user
    end

    def current_user
      db.xquery('SELECT * FROM users WHERE id = ?', session[:user_id]).first
    end

    def update_last_login(user_id)
      db.xquery('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = ?', user_id)
    end

    def buy_product(product_id, user_id)
      db.xquery('INSERT INTO histories (product_id, user_id) VALUES (?, ?)', \
        product_id, user_id)
    end

    def already_bought?(product_id)
      user = current_user
      return false unless user
      count = db.xquery('SELECT count(*) as count FROM histories WHERE product_id = ? AND user_id = ?', \
                        product_id, user[:id]).first[:count]
      count > 0
    end

    def create_comment(product_id, user_id, content)
      db.xquery('INSERT INTO comments (product_id, user_id, content) VALUES (?, ?, ?)', \
        product_id, user_id, content)
    end
  end

  error Ishocon1::AuthenticationError do
    session[:user_id] = nil
    halt 401, erb(:login, layout: false, locals: { message: 'ログインに失敗しました' })
  end

  error Ishocon1::PermissionDenied do
    halt 403, erb(:login, layout: false, locals: { message: '先にログインをしてください' })
  end

  get '/login' do
    session.clear
    erb :login, layout: false, locals: { message: 'ECサイトで爆買いしよう！！！！' }
  end

  post '/login' do
    authenticate(params['email'], params['password'])
    user = current_user
    update_last_login(user[:id])
    redirect '/'
  end

  get '/logout' do
    session[:user_id] = nil
    session.clear
    redirect '/login'
  end

  get '/' do
    page = params[:page].to_i || 0
    last_id = page * 50
    products = db.xquery("SELECT * FROM products where id < #{last_id} ORDER BY id DESC LIMIT 50}")
    # products = db.xquery("SELECT * FROM products ORDER BY id DESC LIMIT 50 OFFSET #{}")
    cmt_query = <<SQL
SELECT *
FROM comments as c
INNER JOIN users as u
ON c.user_id = u.id
WHERE c.product_id = ?
ORDER BY c.created_at DESC
LIMIT 5
SQL
    cmt_count_query = 'SELECT count(*) as count FROM comments WHERE product_id = ?'

    login_user = current_user
    erb :index, locals: { products: products, cmt_query: cmt_query, cmt_count_query: cmt_count_query, user: login_user }
  end

  get '/users/:user_id' do
    products_query = <<SQL
SELECT p.id, p.name, p.description, p.image_path, p.price, h.created_at
FROM histories as h
LEFT OUTER JOIN products as p
ON h.product_id = p.id
WHERE h.user_id = ?
ORDER BY h.id DESC
SQL
    products = db.xquery(products_query, params[:user_id])

    total_pay = 0
    products.each do |product|
      total_pay += product[:price]
    end

    user = db.xquery('SELECT * FROM users WHERE id = ?', params[:user_id]).first

    login_user = current_user
    erb :mypage, locals: { products: products, user: user, total_pay: total_pay, login_user: login_user }
  end

  get '/products/:product_id' do
    product = db.xquery('SELECT * FROM products WHERE id = ?', params[:product_id]).first
    comments = db.xquery('SELECT * FROM comments WHERE product_id = ?', params[:product_id])

    login_user = current_user
    erb :product, locals: { product: product, comments: comments, login_user: login_user }
  end

  post '/products/buy/:product_id' do
    authenticated!
    user = current_user
    buy_product(params[:product_id], user[:id])
    redirect "/users/#{user[:id]}"
  end

  post '/comments/:product_id' do
    authenticated!
    user = current_user
    create_comment(params[:product_id], user[:id], params[:content])
    redirect "/users/#{user[:id]}"
  end

  get '/initialize' do
    db.query('DELETE FROM users WHERE id > 5000')
    db.query('DELETE FROM products WHERE id > 10000')
    db.query('DELETE FROM comments WHERE id > 200000')
    db.query('DELETE FROM histories WHERE id > 500000')
    "Finish"
  end
end
