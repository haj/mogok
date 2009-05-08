
# GIVEN

Given /^I have a torrent with name (.*) and owned by user (.*)$/ do |name, owner|
  if CACHE_ENABLED
    while t = Torrent.find_by_info_hash_hex('54B1A5052B5B7D3BA4760F3BFC1135306A30FFD1')
      t.destroy # force remotion of torrent objects from cache as the test framework bypass cache_money synchronization
    end
  end
  fetch_type 'AUDIO'
  c = fetch_category 'MUSIC', 'AUDIO'
  owner = fetch_user owner
  torrent_file_data = File.new(File.join(TEST_DATA_DIR, 'VALID.TORRENT'), 'rb').read
  t = Torrent.new(:category_id => c.id, :name => name, :user_id => owner.id)  
  t.set_meta_info torrent_file_data, true
  t.save
end

Given /^I have a type with name (.*)$/ do |name|
  fetch_type name
end

Given /^I have a category with name (.*) and with type (.*)$/ do |name, type_name|
  fetch_category name, type_name
end

Given /^I have a format with name (.*) and with type (.*)$/ do |name, type_name|
  fetch_format name, type_name
end

Given /^I have a tag with name (.*) and with category (.*)$/ do |name, category_name|
  fetch_tag name, category_name
end

Given /^the counters for torrent (.*) indicate (\d+) seeders and (\d+) leechers$/ do |name, seeders, leechers|
  t = Torrent.find_by_name name
  t.seeders_count = seeders
  t.leechers_count = leechers
  t.save
end

Given /^the torrent (.*) has been snatched (\d+) times$/ do |name, snatched|
  t = Torrent.find_by_name name
  t.snatches_count = snatched
  t.save
end


# WHEN

When /^I go to the torrent upload page$/ do
  visit 'torrents/upload'
end

When /^I go to the torrent details page for torrent (.*)$/ do |torrent_name|
  torrent = Torrent.find_by_name torrent_name
  visit "torrents/show/#{torrent.id}"
end


# THEN

Then /^the leechers counter for torrent (.*) should be increased by one$/ do |torrent_name|
  t = Torrent.find_by_name torrent_name
  t.leechers_count.should == @leechers_count + 1
end

Then /^the leechers counter for torrent (.*) should be decreased by one$/ do |torrent_name|
  t = Torrent.find_by_name torrent_name
  t.leechers_count.should == @leechers_count - 1
end

Then /^the seeders counter for torrent (.*) should be increased by one$/ do |torrent_name|
  t = Torrent.find_by_name torrent_name
  t.seeders_count.should == @seeders_count + 1
end

Then /^a snatch for torrent (.*) and user (.*) should be created$/ do |torrent_name, username|
  t = Torrent.find_by_name torrent_name
  u = fetch_user username
  snatch = Snatch.find :first, :conditions => {:torrent_id => t, :user_id => u}
  snatch.should_not == nil
end

Then /^the downloaded torrent and the test torrent info hashs should have equal$/ do
  test = Torrent.new
  test_torrent_data = File.new(File.join(TEST_DATA_DIR, 'VALID.TORRENT'), 'rb').read
  test.set_meta_info(test_torrent_data, true)

  downloaded = Torrent.new
  downloaded.set_meta_info(response.body, false) # false because it should contain private flag
  
  downloaded.info_hash.should == test.info_hash
end

Then /^the torrent (.*) should have (\d+) mapped files$/ do |name, mapped_files|
  t = Torrent.find_by_name(name)
  t.mapped_files.size.should == mapped_files.to_i
end

Then /^the torrent (.*) should have (\d+) as piece length$/ do |name, piece_length|
  t = Torrent.find_by_name(name)
  t.piece_length.should == piece_length.to_i
end

Then /^the torrent (.*) should have (\d+) tags$/ do |name, tags|
  t = Torrent.find_by_name(name)
  t.tags.length.should == tags.to_i
end