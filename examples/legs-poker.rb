# Little shoes app I use sometimes to poke at the chat server for debugging
# Mostly just use telnet though...

Shoes.setup do
  gem 'json_pure >= 1.1.1'
end

require 'json/pure.rb'
require 'legs'

Shoes.app(:title => 'Local Legs Poker', :width => 640, :height => 480) do
  @message_log = stack :margin_bottom => 30
  
  flow do
    @input = edit_line(:width => width - 100, :height => 30)
    button("Send", :width => 100, :height => 30) do
      @legs = Legs.new('localhost') unless @legs and @legs.started?
      result = eval("( @legs.#{@input.text.lstrip} )")
      @message_log.append { para result.inspect }
    end
  end
end

