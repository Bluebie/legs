require '../lib/legs'

# This bot just sends message after message to a room called Lounge, for testing clients.

Chat = Legs.new

Chat.set_name "TesterBot"

Chat.join "Lounge"

loop do
  Chat.post_message "Lounge", "This is a test #{rand(999)}"
  sleep(2)
end