require '../lib/legs.rb'

# class to test the marshaling
class Testing
  attr_accessor :a, :b, :c
end

Legs.log = false

# a simple server to test with
Legs.start(6425) do
  def echo(text)
    return text
  end
  
  def count
    caller.meta[:counter] ||= 0
    caller.meta[:counter] += 1
  end
  
  def error
    raise StandardError.new("This is a fake error")
  end
  
  def test_notify
    puts "Success"
  end
  
  def marshal
    obj = Testing.new
    obj.a = 1; obj.b = 2; obj.c = 3
    return obj
  end
  
  def on_disconnect
    puts "#{caller.inspect} disconnected"
  end
  
  def on_connect
    $server_instance = caller
  end
end

## connects and tests a bunch of things
puts "Testing syncronous echo"
i = Legs.new('localhost',6425)
i.meta[:name] = 'first tester client'
puts i.echo('Hello World') == 'Hello World' ?"Success":"Failure"

puts "Testing Count"
puts i.count==1 && i.count == 2 && i.count == 3 ?'Success':'Failure'

puts "Testing count resets correctly"
ii = Legs.new('localhost',6425)
ii.meta[:name] = 'second tester client'
puts ii.count == 1 && ii.count == 2 && ii.count == 3 ?'Success':'Failure'
ii.close!

sleep(0.5)
puts "Testing instance.connected? works well"
puts ii.connected? == false && $server_instance.connected? == false ?'Success':'Failure'

ii = nil
ObjectSpace.garbage_collect

puts "Testing server disconnect worked correctly"
sleep(0.5)
puts Legs.incoming.length == 1 ?'Success':"Failure: #{Legs.users.length}"

puts "Testing async call..."
i.send_async!(:echo, 'Testing') do |r|
  puts r.result == 'Testing' ?'Success':'Failure'
end
sleep(0.5)

puts "Testing async error..."
i.send_async!(:error) do |r|
  begin
    v = r.result
    puts "Failure"
  rescue
    puts "Success"
  end
end
sleep(0.5)

puts "Testing regular error"
v = i.error rescue :good
puts v == :good ?'Success':'Failure'

puts "Testing notify!"
i.test_notify

puts "Testing marshalling"
m = i.marshal
puts m.a == 1 && m.b == 2 && m.c == 3 ?'Success':'Failure'

puts "Testing Legs.connections"
puts (Legs.outgoing.first == i and Legs.connections.length == 2 and Legs.incoming.length == 1) ?'Success':'Failure'

puts "Testing the synced wrapping to the find_by... and broadcast methods in the server object"
puts (Legs.find_user_by_object_id(Legs.incoming.first.__object_id) == Legs.incoming.first) ?'Success':'Failure'

puts "Testing broadcast"
Legs.broadcast :test_notify
sleep(0.5)

puts
puts "Done"
