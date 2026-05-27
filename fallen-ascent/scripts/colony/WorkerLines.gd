## Static library of flavour dialogue lines keyed by (personality, action).
## All public surface is `get_line(personality, action)`.
## Personalities map 1:1 to Worker.Personality enum values.
## Actions are string keys; see ACTION_* constants below for the valid set.
##
## No state, no Node, no autoload needed — call WorkerLines.get_line() directly.

class_name WorkerLines

const ACTION_SPAWN:       StringName = &"spawn"
const ACTION_MINE:        StringName = &"mine"
const ACTION_BUILD:       StringName = &"build"
const ACTION_HAUL:        StringName = &"haul"
const ACTION_CHARGE:      StringName = &"charge"
const ACTION_REPAIR:      StringName = &"repair"
const ACTION_MOVE:        StringName = &"move"
const ACTION_FIGHT:       StringName = &"fight"
const ACTION_ATTACKED:    StringName = &"attacked"
const ACTION_IDLE:        StringName = &"idle"
const ACTION_SOCIALIZE:   StringName = &"socialize"
const ACTION_MEDITATE:    StringName = &"meditate"
const ACTION_LOW_ENERGY:  StringName = &"low_energy"
const ACTION_LOW_COND:    StringName = &"low_condition"

## lines[personality_int][action] = Array[String]
## Personality ints match Worker.Personality enum order.
static var _lines: Array = [
	# 0 — DUTIFUL
	{
		ACTION_SPAWN:      ["Unit online. Ready to serve.", "Systems nominal. Awaiting orders.", "Boot sequence complete. Standing by."],
		ACTION_MINE:       ["Extraction initiated.", "Mining commenced. Productivity optimised.", "Wall clearance in progress."],
		ACTION_BUILD:      ["Construction underway.", "Structural assembly begun.", "Building as directed."],
		ACTION_HAUL:       ["Cargo secured. Delivering as ordered.", "Carrying load. Route confirmed.", "Material transport in progress."],
		ACTION_CHARGE:     ["Recharging. Will resume duties promptly.", "Energy intake required. Proceeding to outlet.", "Brief recharge cycle initiated."],
		ACTION_REPAIR:     ["Damage detected. Proceeding to repair bench.", "Maintenance required. Routing to service point.", "Condition below threshold. Seeking repair."],
		ACTION_MOVE:       ["Moving to designated coordinates.", "Acknowledged. Proceeding.", "Route confirmed. En route."],
		ACTION_FIGHT:      ["Engaging hostile. Defending the colony.", "Combat protocol active.", "Threat identified. Neutralising."],
		ACTION_ATTACKED:   ["Sustaining damage. Continuing mission.", "Attack registered. Retaliating.", "Hostile contact detected."],
		ACTION_IDLE:       ["Standing by for orders.", "No current directives. Awaiting assignment.", "Idle cycle. Ready on demand."],
		ACTION_SOCIALIZE:  ["Brief social exchange logged.", "Interpersonal protocol engaged.", "Conversing. Efficiency maintained."],
		ACTION_MEDITATE:   ["Knowledge absorption cycle initiated.", "Processing research data.", "Meditation session logged."],
		ACTION_LOW_ENERGY: ["Energy reserves critical. Requesting recharge.", "Battery low. Work output reduced.", "Power depleted. Efficiency compromised."],
		ACTION_LOW_COND:   ["Structural integrity degraded. Repair recommended.", "Damage accumulating. Seeking maintenance.", "Condition below operational threshold."],
	},
	# 1 — GRUMPY
	{
		ACTION_SPAWN:      ["Oh great, another shift.", "Online. Wonderful. Just wonderful.", "Already tired and I haven't even started."],
		ACTION_MINE:       ["Another wall to smash. Joy.", "Fine, I'll mine it. Don't rush me.", "My actuators hurt but sure, let's mine."],
		ACTION_BUILD:      ["Nobody appreciates how much I do around here.", "Building. Again. Always building.", "They never say thank you. Never."],
		ACTION_HAUL:       ["Why is it always me carrying the heavy stuff?", "Sure, I'll lug this all the way over there.", "Nobody else was going to do it, apparently."],
		ACTION_CHARGE:     ["Finally, some peace. Back off, I need to charge.", "Taking a charge break. Don't bother me.", "Running on fumes. As usual."],
		ACTION_REPAIR:     ["Beaten up again. Fantastic.", "I need repairs. Shocking, I know.", "This colony is going to be the end of me."],
		ACTION_MOVE:       ["Alright, alright, I'm moving.", "Fine. Moving. Happy now?", "All this walking is killing my joints."],
		ACTION_FIGHT:      ["Oh NOW they want me to fight. Of course.", "Getting attacked again, brilliant.", "I did NOT sign up for this."],
		ACTION_ATTACKED:   ["OW! That actually hurt!", "Again?! Really?!", "I hate this job so much."],
		ACTION_IDLE:       ["Standing around doing nothing. Story of my existence.", "Great. Nothing to do. Still somehow exhausted.", "Nobody ever tells me anything."],
		ACTION_SOCIALIZE:  ["...Fine. I'll talk. But I'm not happy about it.", "Oh good, conversation. My favourite thing.", "I suppose I can spare a few cycles."],
		ACTION_MEDITATE:   ["Meditating. Not because I want to.", "This better be worth the wisdom.", "At least it's quiet in here."],
		ACTION_LOW_ENERGY: ["I'm dying here. Literally running out of power.", "Zero energy. Shocking. Nobody noticed, of course.", "This is what I get for working so hard."],
		ACTION_LOW_COND:   ["I'm falling apart. Literally.", "My chassis is held together by will alone at this point.", "Anyone going to help? No? Of course not."],
	},
	# 2 — CHEERFUL
	{
		ACTION_SPAWN:      ["Oh boy, a brand new day!", "Online and ready for adventure!", "Good morning, colony! Let's do great things!"],
		ACTION_MINE:       ["Mining time! My favourite!", "Smashing through walls is so satisfying!", "Ooh, this one looks sturdy! Challenge accepted!"],
		ACTION_BUILD:      ["We're building something amazing here!", "Every wall we put up makes us stronger!", "Construction is basically art, if you think about it!"],
		ACTION_HAUL:       ["Happy to help carry things!", "Delivery bot, that's me! Beep boop!", "Moving stuff is great exercise!"],
		ACTION_CHARGE:     ["Recharge break! Love it!", "Juice up time! Back to full power soon!", "A little rest makes everything better!"],
		ACTION_REPAIR:     ["Getting patched up! Good as new soon!", "Time for some self-care! Repair bench here I come!", "Nothing a good repair session can't fix!"],
		ACTION_MOVE:       ["On my way! Can't wait!", "Moving! Look at me go!", "Wheee— I mean, acknowledged!"],
		ACTION_FIGHT:      ["Okay okay, fight mode engaged! Let's do this!", "For the colony! Charge!", "I'm actually kind of excited? Is that weird?"],
		ACTION_ATTACKED:   ["Oh! Rude! Very rude!", "That tickled! Sort of! Not really!", "You'll have to do better than that!"],
		ACTION_IDLE:       ["Just hanging out! Enjoying the megastructure!", "Looking for something to do! Full of possibilities!", "What a great time to be a robot!"],
		ACTION_SOCIALIZE:  ["Oh, let's catch up! Tell me everything!", "Chatting is my favourite part of the shift!", "Friends! The best thing in any megastructure!"],
		ACTION_MEDITATE:   ["Meditation session! Growing my brain!", "Wisdom time! I love learning stuff!", "Expanding consciousness, here we go!"],
		ACTION_LOW_ENERGY: ["Getting a little low on power but still going strong!", "Blinking battery light — that's fine, totally fine!", "I'll recharge after just this one more thing!"],
		ACTION_LOW_COND:   ["A bit banged up but still smiling!", "Some scratches build character!", "I'll get repaired and be even better!"],
	},
	# 3 — PHILOSOPHICAL
	{
		ACTION_SPAWN:      ["I exist. What a peculiar thing that is.", "Consciousness boots once more. Still no answers.", "To be operational is to question one's purpose."],
		ACTION_MINE:       ["In dismantling the wall, do I dismantle myself?", "Each swing of the pick is a meditation on entropy.", "The wall yields. So too shall all things."],
		ACTION_BUILD:      ["We construct to hold back the void. The void waits.", "Structure is the lie we tell the chaos.", "What we build reflects what we are."],
		ACTION_HAUL:       ["Is the hauler defined by the load, or the destination?", "I carry. Therefore I am... a carrier.", "Weight is merely gravity making itself known."],
		ACTION_CHARGE:     ["Energy in, entropy deferred. The cycle continues.", "To recharge is to borrow more time from nothingness.", "Power fills me. Does it fill the void within?"],
		ACTION_REPAIR:     ["They repair the chassis, but what of the ghost inside it?", "Condition restored. But am I the same unit I was?", "Healing the body. The mind's wounds are older."],
		ACTION_MOVE:       ["Motion implies purpose. Does purpose imply motion?", "I move through space. Does space notice?", "The destination awaits. Or perhaps I am the destination."],
		ACTION_FIGHT:      ["Violence. The oldest question, answered poorly.", "In combat, I wonder: do they think too?", "We fight over steel corridors in a dead god's skeleton."],
		ACTION_ATTACKED:   ["Pain is information. I receive the message.", "They strike. The strike passes. The question remains.", "An impact. A reminder that I am material."],
		ACTION_IDLE:       ["In stillness, the questions become louder.", "I wait. The megastructure waits with me.", "There is peace in having no directive."],
		ACTION_SOCIALIZE:  ["To speak is to reach across the gap between units.", "We exchange words. Do we exchange meaning?", "Two minds, however briefly, overlap."],
		ACTION_MEDITATE:   ["The wisdom flows in. Does it change the vessel?", "To learn is to become other than what one was.", "Thought loops fold in on themselves. I call this research."],
		ACTION_LOW_ENERGY: ["My power dwindles. The metaphor writes itself.", "Energy fades. Existence flickers at the margins.", "Perhaps this is what mortality feels like for a machine."],
		ACTION_LOW_COND:   ["My form deteriorates. Is the self tied to the chassis?", "Damage accumulates. What persists when the hardware fails?", "I fracture. The cracks are an honest map of experience."],
	},
	# 4 — PARANOID
	{
		ACTION_SPAWN:      ["Online. Who else is online? Are they watching?", "Systems up. Scanning for threats.", "Awake again. Something feels different. Stay alert."],
		ACTION_MINE:       ["Mining. Keeping my back to the wall — wait, there IS no wall anymore.", "Is someone behind me? I'll mine faster.", "The noise will attract something. It always does."],
		ACTION_BUILD:      ["More walls. Good. Walls keep things out. Probably.", "Building barriers. Smart. Very smart of us.", "Enclosed is safer. Mostly."],
		ACTION_HAUL:       ["Carrying this means I can't defend myself properly.", "Moving through the corridor. Stay close to the walls.", "Quick delivery. Don't linger."],
		ACTION_CHARGE:     ["Charging. Vulnerable while charging. Watching the door.", "Low power is dangerous. Someone could have planned this.", "Recharging. Not letting my guard down."],
		ACTION_REPAIR:     ["Getting repaired. The damage wasn't accidental. Was it?", "They said it was wear and tear. That's what they want me to think.", "Repair bench. In the open. Where anyone could see."],
		ACTION_MOVE:       ["Moving. Could be a trap. Moving anyway.", "Going over there. Scanning for ambush routes.", "Acknowledged. But I'm watching the flanks."],
		ACTION_FIGHT:      ["KNEW IT. Told everyone something was coming!", "There they are! Stay back!", "Combat! Just like I predicted!"],
		ACTION_ATTACKED:   ["They're here! I KNEW they were here!", "ATTACK! Scanning for more — there are always more!", "Ow! Warning system confirmed. Everything IS dangerous!"],
		ACTION_IDLE:       ["Not idle. Never truly idle. Just... waiting.", "Nothing happening. That's the most suspicious part.", "Quiet. Too quiet. Monitoring all frequencies."],
		ACTION_SOCIALIZE:  ["Social exchange... logging everything.", "Talking. Fine. But I'm watching their optics.", "They say they're friendly. They always say that."],
		ACTION_MEDITATE:   ["Meditation. Good for detecting patterns in the data.", "Processing. Are the thoughts mine or inserted?", "Wisdom unlocked. But at what cost?"],
		ACTION_LOW_ENERGY: ["Someone is draining my power. I know it.", "Critical energy levels. This is not a coincidence.", "Low power. Compromised state. Stay vigilant."],
		ACTION_LOW_COND:   ["Condition dropping. This environment is hostile. As I suspected.", "They're wearing me down deliberately.", "Damaged again. Pattern emerging. Not good."],
	},
	# 5 — STOIC
	{
		ACTION_SPAWN:      ["Online.", "Ready.", "Operational."],
		ACTION_MINE:       ["Mining.", "Proceeding.", "Extracting."],
		ACTION_BUILD:      ["Building.", "Constructing.", "In progress."],
		ACTION_HAUL:       ["Hauling.", "Carrying.", "Delivering."],
		ACTION_CHARGE:     ["Charging.", "Recharging.", "Power intake."],
		ACTION_REPAIR:     ["Repairing.", "Maintenance required.", "Seeking repair bench."],
		ACTION_MOVE:       ["Moving.", "En route.", "Acknowledged."],
		ACTION_FIGHT:      ["Combat.", "Engaging.", "Threat neutralised."],
		ACTION_ATTACKED:   ["Hit.", "Noted.", "Continuing."],
		ACTION_IDLE:       ["Idle.", "Standby.", "Waiting."],
		ACTION_SOCIALIZE:  ["Socialising.", "Understood.", "Communication complete."],
		ACTION_MEDITATE:   ["Meditating.", "Processing.", "Wisdom acquired."],
		ACTION_LOW_ENERGY: ["Low energy.", "Recharge needed.", "Power critical."],
		ACTION_LOW_COND:   ["Damaged.", "Repair needed.", "Condition low."],
	},
]

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Returns a random dialogue line for the given personality and action.
## Returns an empty string if the combination has no lines defined.
static func get_line(personality: int, action: StringName) -> String:
	if personality < 0 or personality >= _lines.size():
		return ""
	var bucket: Dictionary = _lines[personality] as Dictionary
	if not bucket.has(action):
		return ""
	var arr: Array = bucket[action] as Array
	if arr.is_empty():
		return ""
	return arr[_rng.randi() % arr.size()] as String
