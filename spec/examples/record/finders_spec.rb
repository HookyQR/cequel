# -*- encoding : utf-8 -*-
require_relative 'spec_helper'

describe Cequel::Record::Finders do
  model :Blog do
    key :subdomain, :text
    column :name, :text
    column :description, :text
    column :owner_id, :uuid
  end

  model :User do
    key :login, :text
    column :name, :text
  end

  model :Post do
    key :blog_subdomain, :text
    key :id, :timeuuid, auto: true
    column :title, :text
    column :body, :text
    column :approved, :boolean
    column :read, :boolean
    column :author_id, :uuid, index: true
  end

  let :blogs do
    cequel.batch do
      5.times.map do |i|
        Blog.create!(subdomain: "cassandra#{i}", name: 'Cassandra')
      end
    end
  end

  let(:author_ids) { Array.new(2) { Cequel.uuid }}

  let :cassandra_posts do
    cequel.batch do
      5.times.map do |i|
        Post.create!(
          blog_subdomain: 'cassandra',
          author_id: author_ids[i%2],
          approved: false,
          read: true
        )
      end
    end
  end

  let :postgres_posts do
    cequel.batch do
      5.times.map do |i|
        Post.create!(
          blog_subdomain: 'postgres',
          approved: true,
          read: false
        )
      end
    end
  end

  let(:posts) { cassandra_posts + postgres_posts }

  context 'simple primary key' do

    let!(:blog) { blogs.first }

    describe '#find_by_*' do
      it 'should return matching record' do
        expect(Blog.find_by_subdomain('cassandra0')).to eq(blog)
      end

      it 'should return nil if no record matches' do
        expect(Blog.find_by_subdomain('bogus')).to be_nil
      end

      it 'should respond to method before it is called' do
        expect(User).to be_respond_to(:find_by_login)
      end

      it 'should raise error on wrong name' do
        expect { Blog.find_by_bogus('bogus') }.to raise_error(NoMethodError)
      end

      it 'should not respond to wrong name' do
        expect(User).to_not be_respond_to(:find_by_bogus)
      end
    end

    describe '#find_all_by_*' do
      it 'should raise error if called' do
        expect { Blog.find_all_by_subdomain('outoftime') }
        .to raise_error(NoMethodError)
      end

      it 'should not respond' do
        expect(User).not_to be_respond_to(:find_all_by_login)
      end
    end
  end

  context 'compound primary key' do

    let!(:post) { posts.first }

    describe '#find_all_by_*' do
      it 'should return all records matching key prefix' do
        expect(Post.find_all_by_blog_subdomain('cassandra'))
          .to eq(cassandra_posts)
      end

      it 'should greedily load records' do
        records = Post.find_all_by_blog_subdomain('cassandra')
        disallow_queries!
        expect(records).to eq(cassandra_posts)
      end

      it 'should return empty array if nothing matches' do
        expect(Post.find_all_by_blog_subdomain('bogus')).to eq([])
      end

      it 'should not exist for all keys' do
        expect { Post.find_all_by_blog_subdomain_and_id('f', Cequel.uuid) }
          .to raise_error(NoMethodError)
      end
    end

    describe '#find_by_*' do
      it 'should return record matching all keys' do
        expect(Post.find_by_blog_subdomain_and_id(
          'cassandra', cassandra_posts.first.id)).to eq(cassandra_posts.first)
      end

      it 'should cast arguments to correct type' do
        expect(Post.find_by_blog_subdomain_and_id(
          'cassandra', cassandra_posts.first.id.to_s))
          .to eq(cassandra_posts.first)
      end

      it 'should not exist for key prefix' do
        expect { Post.find_by_blog_subdomain('foo') }
          .to raise_error(NoMethodError)
      end

      it 'should allow lower-order key if chained' do
        expect(Post.where(blog_subdomain: 'cassandra')
                 .find_by_id(cassandra_posts.first.id))
                 .to eq(cassandra_posts.first)
      end
    end

    describe '#with_*' do
      it 'should return record matching all keys' do
        expect(Post.with_blog_subdomain_and_id('cassandra',
                                               cassandra_posts.first.id))
          .to eq(cassandra_posts.first(1))
      end

      it 'should cast arguments to correct type' do
        expect(Post.with_blog_subdomain_and_id('cassandra',
                                               cassandra_posts.first.id.to_s))
          .to eq(cassandra_posts.first(1))
      end

      it 'should return all records matching key prefix' do
        expect(Post.with_blog_subdomain('cassandra'))
          .to eq(cassandra_posts)
      end
    end
  end

  context 'secondary index' do
    before { cassandra_posts }

    it 'should expose scope to query by secondary index' do
      expect(Post.with_author_id(author_ids.first))
        .to match_array(cassandra_posts.values_at(0, 2, 4))
    end

    it 'should expose method to retrieve first result by secondary index' do
      expect(Post.find_by_author_id(author_ids.first))
        .to eq(cassandra_posts.first)
    end

    it 'should expose method to eagerly retrieve all results by secondary index' do
      posts = Post.find_all_by_author_id(author_ids.first)
      disallow_queries!
      expect(posts).to match_array(cassandra_posts.values_at(0, 2, 4))
    end

    it 'should not expose methods for non-indexed columns' do
      [:find_by_title, :find_all_by_title, :with_title].each do |method|
        expect(Post).to_not respond_to(method)
      end
    end
  end

  context 'boolean scope' do
    it 'should provide scoping methods' do
      expect(Post).to respond_to(:where_approved)
      expect(Post).to respond_to(:where_read)
      expect(Post).to respond_to(:where_not_approved)
      expect(Post).to respond_to(:where_not_read)
    end

    RSpec::Matchers.define_negated_matcher :have_records, :be_empty
    RSpec::Matchers.define_negated_matcher :not_be_approved, :be_approved
    RSpec::Matchers.define_negated_matcher :not_be_read, :be_read

    it 'should return the scoped results' do
      posts

      expect(Post.where_approved.all.to_a)
        .to have_records
        .and all be_approved
      expect(Post.where_not_approved.all.to_a)
        .to have_records
        .and all not_be_approved
      expect(Post.where_read.all.to_a)
        .to have_records
        .and all be_read
      expect(Post.where_not_read.all.to_a)
        .to have_records
        .and all not_be_read
    end
  end
end
