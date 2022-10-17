#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'yaml'
require 'json'
require 'mqtt'
require 'gruff'

config = YAML.load_file('config.yml')
connection_string = "mqtt://#{config['mqtt_username']}:#{config['mqtt_password']}@#{config['mqtt_host']}"

ROOM = ARGV[0]
if ROOM.nil?
  puts "Usage: ./record.rb <room>"
  exit 1
end

recording = {}

device_names = config['devices'].map do |d| 
  d.is_a?(Hash) ? [d['id'], d['name']] : [d, d] 
end.to_h

at_exit do
  puts
  filename = "recordings/#{ROOM}.yml"
  puts "Saving recording to #{filename}"
  File.open(filename, 'w') do |f|
    f.write(recording.to_yaml)
  end

  # Fill in any missing indexes with previous row
  recording.each do |room, devices|
    devices.each do |device, data|
      (1..data.length).each do |i|
        data[i] = data[i-1] if data[i].nil?
      end
    end
  end
  # Fill in any missing indexes with next row (in reverse)
  recording.each do |room, devices|
    devices.each do |device, data|
      (data.length-2).downto(0).each do |i|
        data[i] = data[i+1] if data[i].nil?
      end
    end
  end


  puts JSON.pretty_generate(recording)

  # Show min, max, and average distance for each room
  puts
  puts "Summary:"
  puts "---------------------------------------------"
  recording.each do |room, devices|
    puts "[#{room}]:"
    devices.sort_by { |d, _| d }.each do |device, rows|
      puts "    #{device_names[device] || device}:"
      distances = rows.compact.map { |row| row[1] }
      puts "         distance => min: #{distances.min}, max: #{distances.max}, mean: #{distances.sum / distances.size}"
      rssi = rows.compact.map { |row| row[0] }
      puts "         RSSI     => min: #{rssi.min}, max: #{rssi.max}, mean: #{rssi.sum / rssi.size}"
    end
  end
  puts "---------------------------------------------"

  puts "Generating graph..."
  g = Gruff::Line.new
  g.title = 'Distance'
  # g.data :Jimmy, [25, 36, 86, 39, 25, 31, 79, 88]
  
  recording.each do |room, devices|
    devices.each do |device, rows|
      next unless device == 'nathans_iphone'
      g.data "#{room} - #{device_names[device] || device}", rows.map { |row| row[1] }
    end
  end
  g.write("recordings/#{ROOM}.png")
end

current_time = Time.now.to_i

puts "Connecting to #{config['mqtt_host']}..."
client = MQTT::Client.connect(connection_string) do |c|
  c.get('espresense/devices/#') do |topic, message_string| 
    # espresense/devices/mashas_iphone/nathans_office
    device = topic.split('/')[2]
    room = topic.split('/')[3]
    next unless device_names.keys.include?(device)
    # puts "#{topic}: #{message}"

    elapsed_seconds = Time.now.to_i - current_time
     
    message = JSON.parse(message_string)
    recording[room] ||= {}
    recording[room][device] ||= []

    next_row = [ message['rssi'], message['distance'] ]

    puts "[#{room}] #{device_names[device] || device}: #{next_row.join(', ')}"
    # recording[room][device] << next_row
    recording[room][device][elapsed_seconds] = next_row
  end
end

# Path: config.yml
# Compare this snippet from Gemfile:
# # frozen_string_literal: true
# 
# source 'https://rubygems.org'
# git_source(:github) do |repo_name|
#   repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?('/')
#   "
