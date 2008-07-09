require '../lib/legs'

# This is how simple a Legs server can look.

Legs.start do
  def echo(text)
    return text
  end
end

sleep

# To test this server, first, run it in ruby, and then open another terminal, telnet localhost 30274
# Then enter:
#   {"method":"echo","params":["Hello World"],"id":1}
# result should be:
#   {"result":"Hello World","id":1}
# however the properties may appear in a different order, this makes no difference.

# Test to ensure there are no security flaws...
# Try {"method":"object_id","params":[],"id":1}
# Should return: {"error":"Cannot run 'object_id' because it is not defined in this server","id":1}
# And try: {"method":"caller","params":[],"id":1}
# Should recieve a similar error response. :)