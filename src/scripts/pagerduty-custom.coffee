pagerduty = require('../pagerduty')
{ first, last, pick } = require('lodash')

userSupportId = process.env.HUBOT_PAGERDUTY_SCHEDULE_USERSUP_ID
platformId = process.env.HUBOT_PAGERDUTY_SCHEDULE_PLATFORM_ID
escalationId = process.env.HUBOT_PAGERDUTY_SCHEDULE_ESCALATION_ID

oneDayMs = 24 * 3600 * 1000
weekMs = 7 * oneDayMs

filterUserSupport = (oncall) -> oncall.schedule.id is userSupportId
filterPlatform    = (oncall) -> oncall.schedule.id is platformId
filterIncidentCmd = (oncall) -> oncall.schedule.id is escalationId


# selects the right oncall based on current time
findOncall = (oncalls, timeFrame, now) ->
  nowIso = new Date(now).toISOString()
  if timeFrame in ['was', 'before']
    return last(oncalls.filter((oncall) ->
      oncall.end < nowIso
    )) # last oncall.end before now

  if timeFrame in ['next', 'after']
    return first(oncalls.filter((oncall) ->
      oncall.start > nowIso
    )) # first oncall.start after now

  return oncalls.find((oncall) ->
    oncall.start < nowIso < oncall.end
  )


findIncidentCmd = (oncalls, timeFrame, now) ->
  if timeFrame in ['before', 'after', 'now']
    # follow the sorted list of shifts
    return findOncall(oncalls, timeFrame, now)

  found = null
  nowMinus24h = new Date(now - oneDayMs).toISOString()
  nowPlus24h = new Date(now + oneDayMs).toISOString()

  if timeFrame is 'was'
    found = last(oncalls.filter((oncall) ->
      oncall.end > nowMinus24h
    ))

  if timeFrame is 'next'
    found = first(oncalls.filter((oncall) ->
      oncall.start < nowPlus24h
    ))

  return found || findOncall(oncalls, 'now', now)


# formats time to show the name of the day, month, day and time
formatTime = (date) ->
  dateTime = new Date(date).toString()
  return "#{dateTime.substring(0, 10)} #{dateTime.substring(16, 21)}"


# according to requesed time (on call, now, on call next, was on call) prepares time query
# pagerduty limits the amount of returned data, so more precise time settings
setTimeQuery = (timeFrame, now)  ->
  nowIso = new Date(now).toISOString()
  plusMinute = new Date(now + 60000).toISOString()

  past = new Date(now - weekMs).toISOString()
  future = new Date(now + weekMs).toISOString()

  if timeFrame in ['was', 'before']
    return { since: past, untilParam: nowIso, timeFrame }

  if timeFrame in ['next', 'after']
    return { since: nowIso, untilParam: future, timeFrame }

  return { since: nowIso, untilParam: plusMinute, timeFrame }


sortByStartEndAsc = (a, b) ->
  if a.start > b.start
    return 1
  if a.start < b.start
    return -1
  if a.end > b.end
    return 1
  if a.end < b.end
    return -1
  if a.schedule.id > b.schedule.id
    return 1
  if a.schedule.id < b.schedule.id
    return -1
  return 0


getCustomOncalls = (timeFrame, msg) ->
  if not msg?
    console.log('no msg sent')
    return

  timeNow = Date.now()
  timeQuery = setTimeQuery(timeFrame, timeNow)

  # a week long of oncalls has much more shifts:
  # 7 days * 3 escalation-layers * 3 services = 63 oncalls
  # plus added 3 layers of Incident-Command-Week-long
  # Sum it up and you end-up at 66 "oncalls".
  # We want to give it some space for overrides, 100 seems reasonable
  query = {
    limit: 100,
    time_zone: 'UTC',
    "schedule_ids[]": [userSupportId, platformId, escalationId],
    since: timeQuery.since,
    until: timeQuery.untilParam,
    earliest: true,
  }

  pagerduty.get('/oncalls', query, (err, json) ->
    if err
      msg.send('Error:' + err)
      return

    escalationLevelOne = json.oncalls.filter((oncall) ->
      return oncall.escalation_level == 1
    )

    userSupports = escalationLevelOne.filter(filterUserSupport).sort(sortByStartEndAsc)
    platformOncalls = escalationLevelOne.filter(filterPlatform).sort(sortByStartEndAsc)
    incidentCmds = escalationLevelOne.filter(filterIncidentCmd).sort(sortByStartEndAsc)

    userSupport = findOncall(userSupports, timeFrame, timeNow)
    platformOncall = findOncall(platformOncalls, timeFrame, timeNow)

    # custom logic for escallations, because they have week-long shifts
    # and we basically loaded either a week before, or week after today
    incidentCmd = findIncidentCmd(incidentCmds, timeFrame, timeNow)

    message = "#{userSupport.schedule.summary} - #{formatTime(userSupport.start)} - #{formatTime(userSupport.end)} - *#{userSupport.user.summary}*\n"
    message += "#{platformOncall.schedule.summary} - #{formatTime(platformOncall.start)} - #{formatTime(platformOncall.end)} - *#{platformOncall.user.summary}*\n"
    message += "#{incidentCmd.schedule.summary} - #{formatTime(incidentCmd.start)} - #{formatTime(incidentCmd.end)} - *#{incidentCmd.user.summary}*\n"

    msg.send(message)
    return
  )
  return

getCustomOncalls.findOncall = findOncall
getCustomOncalls.findIncidentCmd = findIncidentCmd
getCustomOncalls.formatTime = formatTime
getCustomOncalls.setTimeQuery = setTimeQuery

module.exports = getCustomOncalls
