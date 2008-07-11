# Shoes Chat Client is a generic irc-like chat system, made in Legs and Shoes, as a way to find
# any troublesome parts in Legs and learn stuff about Shoes. :)

#HOSTNAME = 'localhost'
HOSTNAME = 'bluebie.creativepony.com'


Shoes.setup do
  gem 'json_pure >= 1.1.1'
end

require 'json/pure.rb'
require '../lib/legs'

# This add's some methods the server can call on to notify us of events like a new message
Legs.start false do
  attr_accessor :app, :rooms
  
  def user_left room_name, user
    @rooms[room_name]['users'].delete_if { |u| u['id'] == user['id'] }
  end
  
  def user_joined room_name, user
    @rooms[room_name]['users'].push user unless @rooms[room_name]['users'].include?(user)
  end
  
  def room_created room
    @app.add_room room
  end
  
  def room_changed room
    @app.update_room room.delete('name'), room
  end
  
  def user_changed user
    @rooms.each do |room|
      room['users'].map! do |room_user|
        if user['id'] == room_user['id']
          user
        else
          room_user
        end
      end
    end
    #@app.update_user_list
  end
  
  def room_message room, message
    @app.add_message message
  end
end


class LegsChat < Shoes
  url '/', :index
  url '/room/(\w+)', :room
  
  Chat = Legs.new(HOSTNAME)
  
  def index
    #Legs.server_object.app = self
    #name = ask("What's your name?")
    #Chat.notify! :set_name, name
    
    @@room_data = Chat.rooms
    @@joined_rooms = []
    @@available_rooms = @@room_data.keys
    visit('/room/Lobby')
  end
  
  def room name
    unless @@joined_rooms.include? name
      @@room_data[name] = Chat.join(name)
      @@joined_rooms.push name
    end
    
    @room = name
    timer(0.5) { layout } # don't know why I need this, but layout goes all weird without delay
  end
  
  def layout
    clear do
      background white
      
      @rooms_list = stack :width => 180, :height => 1.0
      stack do
        @log = stack :width => -360, :height => -30, :scroll => true, :margin_right => gutter
        
        flow :margin_right => gutter, :height => 30 do
          @msg_input = edit_line(:width => -100)
          
          submit = Proc.new do
            add_message @room, Chat.post_message(@room, @msg_input.text)
            @msg_input.text = ''
          end
          
          button("Send", :width => 100, &submit)
        end

      end
      @users_list = stack :width => 180, :height => 1.0
    end
    
    @@available_rooms.each { |r| add_room r }
    @@room_data[@room]['messages'].each { |m| add_message @room, m }
  end
  
  
  # adds a message to the display
  def add_message room_name, message
    unless @@room_data[room_name]['messages'].include? message
      messages = @@room_data[room_name]['messages']
      messages.push message
      @@room_data[room_name]['messages'] = messages[-500,500] if messages.length > 500
    end
    
    return if room_name != @room
    scroll_down = @log.scroll_top >= @log.scroll_max - 10
    @log.append do
      flow do
        para strong(message['user']['name'] || message ['user']['id']), ':  ', message['message']
      end
    end
    
    while @log.contents.length > 500
      @log.contents.first.remove
    end
    
    @log.scroll_top = @log.scroll_max
  end
  
  
  # adds a room to the sidebar
  def add_room room_name
    @@available_rooms.push room_name unless @@available_rooms.include? room_name
    @rooms_list.append do
      flow :margin => 5 do
        # _why assures me the :checked style will work in the next release
        joined = check :checked => @@joined_rooms.include?(room_name) do |chk|
          @@joined_rooms.push(room_name) and @@room_data[room_name].merge! Chat.join(room_name) if chk.checked?
          Chat.leave(room_name) and @@joined_rooms.delete(room_name) unless chk.checked?
        end
        
        para room_name, :underline => (@room == room_name ? :one : false)
        
        click do
          visit("/room/#{room_name}")
        end unless @room == room_name
      end
    end
  end
  
  def update_room room_name, data
    @@room_data[room_name].merge! data
  end
end

Shoes.app(:title => "Legs Chat", :width => 700, :height => 350)

