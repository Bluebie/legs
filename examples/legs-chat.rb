# Will eventually be a reasonably functional irc-like chat client with rooms and stuff

Shoes.setup do
  gem 'json_pure >= 1.1.1'
end

require 'json/pure.rb'
require 'legs'

class LegsChatClient; class << self
  @@rooms = {}
  
  def user_left room_name, user
    @@rooms[room_name]['users'].delete_if { |u| u['id'] == user['id'] }
  end
  
  def user_joined room_name, user
    @@rooms[room_name]['users'].push user
  end
  
  def room_message room_name, from, message
    @@rooms[room_name]['messages']
  end
  
end; end

class LegsChat < Shoes
  url '/', :index
  url '/room/(\w+)', :room
  
  LEGS = LegsChatClient.new('localhost')
  
  def index
    @@rooms = {}
    LEGS.available_rooms.each do |room|
      @@rooms[room] = {}
    end
    
    visit("/room/#{@@rooms.first}")
  end
  
  def room name
    
    stack :width => 180, :margin => 10 do
      @@rooms.each_pair do |rn, data|
        flow :margin => 3, :radius => 3 do
          if rn == name
            background black
            fill white
          end
          
          check = check_box do
            @@rooms[rn].merge!(LEGS.join(rn)) if checked?
            LEGS.leave(rn) and @@rooms[rn] = {} unless checked?
          end
          
          check.checked = !data.empty?
          
          para rn
          
          click do
            visit("/room/#{rn}") if check.checked?
          end
        end
      end
    end
    
    stack do
      @logger = stack do
        
      end
      flow do
        @msg_input = edit_line(:width => width - 100, :height => 30)
        button("Send", :width => 100, :height => 30) do
          LEGS.post_message(name, @msg_input) and @msg_input.text = ''
        end
      end
    end
  end
end

Shoes.app :title => "Legs Chat", :width => 700, :height => 350

