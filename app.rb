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
    t.integer :books_pending_total_cents, default: 0
    t.integer :books_published_total_cents, default: 0
  end

  create_table :books, id: :serial, force: true do |t|
    t.string :title
    t.integer :status, default: 0
    t.integer :price_cents, default: 0

    t.belongs_to :author, index: true
  end
end

class CreateBookWorker
  include Sidekiq::Worker

  def perform(id)
    author = Author.find(id)
    author.books.create!(title: "Book 2", status: [0, 1].sample, price_cents: rand(1000..10000))
  end
end


class Book < ActiveRecord::Base
  belongs_to :author

  counter_culture :author,
    # execute_after_commit: true,
    column_name: -> (b) { "books_#{b.status}_count" },
    column_names: -> {
      {
        Book.pending => :books_pending_count,
        Book.published => :books_published_count,
      }
    }

  counter_culture :author,
    # execute_after_commit: true,
    column_name: -> (b) { "books_#{b.status}_total_cents" },
    column_names: -> {
      {
        Book.pending => :books_pending_total_cents,
        Book.published => :books_published_total_cents,
      }
    }

  enum status: { pending: 0, published: 1 }

  after_commit :update_name, on: :create

  def update_name
    self.author.with_lock do
      #
    end
  end
end

class Author < ActiveRecord::Base
  has_many :books

  def create_book
    CreateBookWorker.perform_async(self.id)
  end
end

class BugTest < Minitest::Test
  def test_bug_locking_a_record_with_unpersisted
    Sidekiq::Testing.inline! do
      author = Author.create!(name: "John")
      author.create_book
    end
  end
end
