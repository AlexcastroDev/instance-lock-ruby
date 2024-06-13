# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  # gem "sqlite3"
  # Activate the gem you are reporting the issue against.
  gem "activerecord", "7.1.2"
  gem "pg"
  gem "counter_culture"
  gem "after_commit_action"
  gem 'sidekiq'
end

require "active_record"
require "minitest/autorun"
require "logger"
require 'sidekiq/api'
require 'sidekiq/testing'
# This connection will do for database-independent bug reports.
# ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  encoding: "unicode",
  database: ENV["DB_NAME"],
  username: "postgres",
  password: "",
  host: ENV["DB_HOST"],
)


ActiveRecord::Base.logger = Logger.new(STDOUT)

ActiveRecord::Schema.define do
  create_table :authors, id: :serial, force: true do |t|
    t.string :name

    t.integer :books_pending_count, default: 0
    t.integer :books_published_count, default: 0
    t.integer :books_published_total_cents, default: 0
  end

  create_table :books, id: :serial, force: true do |t|
    t.string :title
    t.integer :status, default: 0
    t.integer :sales_count, default: 0

    t.belongs_to :author, index: true
  end

  create_table :sales, id: :serial, force: true do |t|
    t.integer :price_cents, default: 0

    t.belongs_to :book, index: true
  end
end

class CreateBookWorker
  include Sidekiq::Worker

  def perform(id)
    author = Author.find(id)
    author.books.create!(title: "Ruby", status: :published)
  end
end

class SellBookWorker
  include Sidekiq::Worker

  def perform(book_id, price)
    book = Book.find(book_id)
    book.sales.create!(price_cents: price)
  end
end


class Book < ActiveRecord::Base
  belongs_to :author
  has_many :sales

  counter_culture :author,
    # execute_after_commit: true,
    column_name: -> (b) { "books_#{b.status}_count" },
    column_names: -> {
      {
        Book.pending => :books_pending_count,
        Book.published => :books_published_count,
      }
    }

  enum status: { pending: 0, published: 1 }
end


class Author < ActiveRecord::Base
  has_many :books
  has_many :sales, through: :books

  def sell(book_id:, price:)
    SellBookWorker.perform_async(book_id, price)
  end
end

class Sale < ActiveRecord::Base
  belongs_to :book
  belongs_to :author

  counter_culture [:book, :author],
    column_name: 'books_published_total_cents',
    delta_column: 'price_cents'

  counter_culture :book, column_name: 'sales_count'

  after_commit :update_name, on: :create

  def update_name
    self.book.with_lock do
      #
    end
  end
end


class BugTest < Minitest::Test
  def test_bug_locking_a_record_with_unpersisted
    # 100.times do
      Sidekiq::Testing.inline! do
        author = Author.create!(name: "John")
        author.books.create!(title: "Ruby", status: :pending)
        book = author.books.last

        author.sell(book_id: book.id, price: 10000)

        author.reload
        book.reload

        assert_equal 10000, author.books_published_total_cents
        assert_equal 1, book.sales_count
      end
    # end
  end
end
