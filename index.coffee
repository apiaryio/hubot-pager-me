fs = require 'fs'
path = require 'path'

module.exports = (robot, scripts) ->
  scriptsPath = path.resolve(__dirname, 'src', 'scripts')
  fs.exists scriptsPath, (exists) ->
    if exists
      for script in fs.readdirSync(scriptsPath)
        if scripts? and '*' not in scripts
          robot.loadFile(scriptsPath, script) if script in scripts
        else
          robot.loadFile(scriptsPath, script)

if require.main == module
  console.log('Hubot Pager Me Loaded as primary module')

  # a dummy robot that can not do much
  robot = {
    functions: []
    send: (txt) ->
      console.log('Hubot answer:')
      console.log(txt)
      return
  }

  pagerduty = require('./src/pagerduty')
  if pagerduty.missingEnvironmentForApi(robot)
    return

  robot.receive = (msg) ->
    res = null
    filtered = robot.functions.filter((setup) ->
      temp = msg.match(setup.regex)
      if temp != null
        res = temp
        return true
    )
    if res != null
      console.log('Found a message match!')
    if filtered.length > 1
      console.log("Possible issue with RegExp matching: #{filtered.length} matches found!")
    return { filtered, res }

  robot.respond = (regex, fn) ->
    robot.functions.push({ regex, fn })
    return

  robot.loadFile = (pathToScript, scriptFileName) ->
    resolvedPathToScript = path.join(pathToScript, scriptFileName)
    fn = require(resolvedPathToScript)
    fn(robot)
    return


  inp = process.argv[process.argv.length - 1]

  setTimeout(() ->
    # load the hubot scripts
    module.exports(robot)
    return
  , 10)
  setTimeout(() ->
    # run a custom message parsing
    parsed = robot.receive(if (inp.indexOf('coffee') > -1) then "who's oncall" else inp)
    if parsed.res == null
      console.log('No match')
    else
      command = parsed.filtered[0]
      command.fn(robot)
    return
  , 500)
