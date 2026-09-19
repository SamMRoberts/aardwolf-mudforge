table.insert(TEST.loadedPlugins, { id = "aardwolf-ui-reference", enabled = true })
on("aardwolf.core.consumer.declare", function(payload)
  emit("aardwolf.core.consumer.registration", {
    consumerId = payload.consumerId,
    ok = true,
    protocol = 1,
    version = "0.3.0",
    apiVersion = "0.3.0",
    capabilities = { ui = { version = 1 } },
  })
end)

init()
TEST.assert_equal(TEST.nextWidget, 2, "reference creates HTML and canvas windows")
TEST.assert_equal(TEST.widgets["widget-1"].config.type, "html", "reference HTML window type")
TEST.assert_equal(TEST.widgets["widget-2"].config.type, "canvas", "reference canvas window type")
TEST.assert_equal(TEST.widgets["widget-1"].bindings.message, "Dynamic text is supplied through a binding.", "reference binds dynamic HTML text")
TEST.assert_true(#TEST.draws >= 3, "reference draws initial canvas")

TEST.widgets["widget-1"].events.action({ action = "acknowledge" })
TEST.assert_equal(TEST.widgets["widget-1"].bindings.message, "Acknowledged without replacing the document.", "reference action updates binding")
local draws_before_resize = #TEST.draws
TEST.widgets["widget-2"].events.resize({ width = 500, height = 240 })
TEST.assert_true(#TEST.draws > draws_before_resize, "reference redraws canvas on resize")

TEST.commands["awui-reference"].callback("")
TEST.assert_true(TEST.widgets["widget-1"].visible, "reference command shows HTML")
TEST.assert_true(TEST.widgets["widget-2"].visible, "reference command shows canvas")
TEST.commands["awui-reference"].callback("hide")
TEST.assert_equal(TEST.widgets["widget-1"].visible, false, "reference command hides HTML")
TEST.assert_equal(TEST.widgets["widget-2"].visible, false, "reference command hides canvas")

cleanup()
TEST.assert_nil(TEST.widgets["widget-1"], "reference cleanup destroys HTML")
TEST.assert_nil(TEST.widgets["widget-2"], "reference cleanup destroys canvas")
