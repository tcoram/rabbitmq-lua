rb=require "amqp-util"

conn = rb.connect_rabbit{host="localhost"}
rb.declare_exchange(conn, "LuaExchange", "fanout")
rb.bind_queue(conn, "LuaQueue","LuaExchange")
rb.bind_queue(conn, "LuaQueue2","LuaExchange")

function qprint(consumer_tag,data)
   io.write(string.format("tag=%s, data=%s\n",consumer_tag,data))
end

consumers = {LuaQueue = rb.create_consumer(conn,"LuaQueue",qprint),
	     LuaQueue2 = rb.create_consumer(conn,"LuaQueue2",qprint)}
rb.wait_for_messages(conn,consumers)

