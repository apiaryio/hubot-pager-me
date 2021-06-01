pagerduty = require('../pagerduty')
{ first, last, pick } = require('lodash')


primaryId = process.env.HUBOT_PAGERDUTY_SCHEDULE_PLATFORM_ID
secondaryId = process.env.HUBOT_PAGERDUTY_SCHEDULE_ESCALATION_ID

oneDayMs = 24 * 3600 * 1000
weekMs = 7 * oneDayMs


filterPrimary    = (oncall) -> oncall.schedule.id is primaryId
filterSecondary  = (oncall) -> oncall.schedule.id is secondaryId


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
    "schedule_ids[]": [primaryId, secondaryId],
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

    escalationLevelTwo = json.oncalls.filter((oncall) ->
      return oncall.escalation_level == 2
    )

    primaryOncalls = escalationLevelOne.filter(filterPrimary).sort(sortByStartEndAsc)
    secondaryOncalls = escalationLevelTwo.filter(filterSecondary).sort(sortByStartEndAsc)

    primaryOncall = findOncall(primaryOncalls, timeFrame, timeNow)
    secondaryOncall = findOncall(secondaryOncalls, timeFrame, timeNow)
    if primaryOncall && secondaryOncall
      message = ""
      message += "#{primaryOncall.schedule.summary} - #{formatTime(primaryOncall.start)} - #{formatTime(primaryOncall.end)} - *#{primaryOncall.user.summary}*\n"
      message += "#{secondaryOncall.schedule.summary} - #{formatTime(secondaryOncall.start)} - #{formatTime(secondaryOncall.end)} - *#{secondaryOncall.user.summary}*\n"

      msg.send(message)
      return
    else
      msg.send('Error no data in findOncall, query:', query)
  )
  return

getCustomOncalls.findOncall = findOncall
getCustomOncalls.formatTime = formatTime
getCustomOncalls.setTimeQuery = setTimeQuery

module.exports = getCustomOncalls
