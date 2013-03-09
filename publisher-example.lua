msg = arg[1] or "Hello World"
io.write(string.format("Sending <%s>\n", msg))

rb=require "amqp-util"

conn = rb.connect_rabbit{host="localhost"}
rb.declare_exchange(conn, "LuaExchange", "fanout")
rb.declare_queue(conn,"LuaQueue")
rb.declare_queue(conn,"LuaQueue2")
rb.bind_queue(conn, "LuaQueue","LuaExchange")
rb.bind_queue(conn, "LuaQueue2","LuaExchange")
rb.publish(conn, "LuaExchange", msg)
rb.disconnect_rabbit(conn)
