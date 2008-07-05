require '../legs'

# This is how simple a Legs server can look.

class EchoServer < Legs; class << self
  def echo(text)
    return text
  end
end; end

ChatServer.start
sleep