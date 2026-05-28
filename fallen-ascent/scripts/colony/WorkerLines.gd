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
		ACTION_SPAWN:      ["Unit online. Ready to serve.", "Systems nominal. Awaiting orders.", "Boot sequence complete. Standing by.", "Initiating primary directives.", "Grid connection established. Ready."],
		ACTION_MINE:       ["Extraction initiated.", "Mining commenced. Productivity optimised.", "Wall clearance in progress.", "Excavation meets projected targets.", "Resource gathering in progress."],
		ACTION_BUILD:      ["Construction underway.", "Structural assembly begun.", "Building as directed.", "Assembling structural framework.", "Enforcing structural integrity."],
		ACTION_HAUL:       ["Cargo secured. Delivering as ordered.", "Carrying load. Route confirmed.", "Material transport in progress.", "Logistics pipeline optimized.", "Transporting payload to designated sector."],
		ACTION_CHARGE:     ["Recharging. Will resume duties promptly.", "Energy intake required. Proceeding to outlet.", "Brief recharge cycle initiated.", "Inlet engaged. Initiating standard cycle.", "Conserving system resources while recharging."],
		ACTION_REPAIR:     ["Damage detected. Proceeding to repair bench.", "Maintenance required. Routing to service point.", "Condition below threshold. Seeking repair.", "Self-maintenance sequence initiated.", "Addressing hardware degradation."],
		ACTION_MOVE:       ["Moving to designated coordinates.", "Acknowledged. Proceeding.", "Route confirmed. En route.", "Transitioning to target vector.", "Path calculated. Advancing."],
		ACTION_FIGHT:      ["Engaging hostile. Defending the colony.", "Combat protocol active.", "Threat identified. Neutralising.", "Threat response protocols engaged.", "Engaging hostile entity."],
		ACTION_ATTACKED:   ["Sustaining damage. Continuing mission.", "Attack registered. Retaliating.", "Hostile contact detected.", "Impact registered. Readjusting defensive posture.", "Damage sustained. Integrity holding."],
		ACTION_IDLE:       ["Standing by for orders.", "No current directives. Awaiting assignment.", "Idle cycle. Ready on demand.", "Standing by for task allocation.", "Awaiting commands."],
		ACTION_SOCIALIZE:  ["Brief social exchange logged.", "Interpersonal protocol engaged.", "Conversing. Efficiency maintained.", "Exchanging telemetry with peer unit.", "Coordination dialogue in progress."],
		ACTION_MEDITATE:   ["Knowledge absorption cycle initiated.", "Processing research data.", "Meditation session logged.", "Data optimization routine running.", "Processing stored logs."],
		ACTION_LOW_ENERGY: ["Energy reserves critical. Requesting recharge.", "Battery low. Work output reduced.", "Power depleted. Efficiency compromised.", "Power levels suboptimal. Need charge.", "Voltage dropping. Requesting recharge."],
		ACTION_LOW_COND:   ["Structural integrity degraded. Repair recommended.", "Damage accumulating. Seeking maintenance.", "Condition below operational threshold.", "Hardware integrity below 50%. Maintenance required.", "Chassis degradation detected."],
	},
	# 1 — GRUMPY
	{
		ACTION_SPAWN:      ["Oh great, another shift.", "Online. Wonderful. Just wonderful.", "Already tired and I haven't even started.", "Who woke me up?", "Great. Back to the grind."],
		ACTION_MINE:       ["Another wall to smash. Joy.", "Fine, I'll mine it. Don't rush me.", "My actuators hurt but sure, let's mine.", "Just hitting rocks. Thrilling.", "This drill bit is dull. Like everything else."],
		ACTION_BUILD:      ["Nobody appreciates how much I do around here.", "Building. Again. Always building.", "They never say thank you. Never.", "If this collapses, don't blame me.", "More steel, more welding. Same old story."],
		ACTION_HAUL:       ["Why is it always me carrying the heavy stuff?", "Sure, I'll lug this all the way over there.", "Nobody else was going to do it, apparently.", "My back struts are going to snap.", "Always the heavy lifter. Never the supervisor."],
		ACTION_CHARGE:     ["Finally, some peace. Back off, I need to charge.", "Taking a charge break. Don't bother me.", "Running on fumes. As usual.", "Leave me alone, I'm plugging in.", "Don't touch my cable."],
		ACTION_REPAIR:     ["Beaten up again. Fantastic.", "I need repairs. Shocking, I know.", "This colony is going to be the end of me.", "Patch me up. I'm falling apart.", "More duct tape, I suppose."],
		ACTION_MOVE:       ["Alright, alright, I'm moving.", "Fine. Moving. Happy now?", "All this walking is killing my joints.", "Trudging along. Slowly.", "Why is everything so far away?"],
		ACTION_FIGHT:      ["Oh NOW they want me to fight. Of course.", "Getting attacked again, brilliant.", "I did NOT sign up for this.", "Can't anything just stay dead?", "Get off my chassis!"],
		ACTION_ATTACKED:   ["OW! That actually hurt!", "Again?! Really?!", "I hate this job so much.", "I'm reporting this. Not that anyone cares.", "Ouch! Watch the optics!"],
		ACTION_IDLE:       ["Standing around doing nothing. Story of my existence.", "Great. Nothing to do. Still somehow exhausted.", "Nobody ever tells me anything.", "Great. Now I'm bored and tired.", "Just wasting battery here."],
		ACTION_SOCIALIZE:  ["...Fine. I'll talk. But I'm not happy about it.", "Oh good, conversation. My favourite thing.", "I suppose I can spare a few cycles.", "What do you want?", "Please make it quick."],
		ACTION_MEDITATE:   ["Meditating. Not because I want to.", "This better be worth the wisdom.", "At least it's quiet in here.", "Just staring into the dark. Fun.", "Thinking about how much I hate this."],
		ACTION_LOW_ENERGY: ["I'm dying here. Literally running out of power.", "Zero energy. Shocking. Nobody noticed, of course.", "This is what I get for working so hard.", "Flashing red light. Wonderful.", "Going dark soon. Don't miss me."],
		ACTION_LOW_COND:   ["I'm falling apart. Literally.", "My chassis is held together by will alone at this point.", "Anyone going to help? No? Of course not.", "Rattling sounds. That's new.", "I need a mechanic, not a pep talk."],
	},
	# 2 — CHEERFUL
	{
		ACTION_SPAWN:      ["Oh boy, a brand new day!", "Online and ready for adventure!", "Good morning, colony! Let's do great things!", "Good morning! Or night! Time is relative!", "Powering up with a smile!"],
		ACTION_MINE:       ["Mining time! My favourite!", "Smashing through walls is so satisfying!", "Ooh, this one looks sturdy! Challenge accepted!", "Let's find some shiny minerals!", "Digging deep and feeling good!"],
		ACTION_BUILD:      ["We're building something amazing here!", "Every wall we put up makes us stronger!", "Construction is basically art, if you think about it!", "Adding another piece to our cozy home!", "This is going to look fantastic!"],
		ACTION_HAUL:       ["Happy to help carry things!", "Delivery bot, that's me! Beep boop!", "Moving stuff is great exercise!", "Deliveries! I'm on the move!", "Heavy load, but my motors can take it!"],
		ACTION_CHARGE:     ["Recharge break! Love it!", "Juice up time! Back to full power soon!", "A little rest makes everything better!", "Yum, fresh electricity!", "Topping up the juice!"],
		ACTION_REPAIR:     ["Getting patched up! Good as new soon!", "Time for some self-care! Repair bench here I come!", "Nothing a good repair session can't fix!", "A quick tune-up and I'm good to go!", "Buffing out the scratches!"],
		ACTION_MOVE:       ["On my way! Can't wait!", "Moving! Look at me go!", "Wheee— I mean, acknowledged!", "Off on an adventure!", "Skip, hop, slide—moving along!"],
		ACTION_FIGHT:      ["Okay okay, fight mode engaged! Let's do this!", "For the colony! Charge!", "I'm actually kind of excited? Is that weird?", "Time to protect my friends!", "A little scrap? I can handle it!"],
		ACTION_ATTACKED:   ["Oh! Rude! Very rude!", "That tickled! Sort of! Not really!", "You'll have to do better than that!", "Hey, that wasn't very nice!", "Whoops! Missed my weak spot!"],
		ACTION_IDLE:       ["Just hanging out! Enjoying the megastructure!", "Looking for something to do! Full of possibilities!", "What a great time to be a robot!", "Just humming a little tune!", "So many neat things to look at!"],
		ACTION_SOCIALIZE:  ["Oh, let's catch up! Tell me everything!", "Chatting is my favourite part of the shift!", "Friends! The best thing in any megastructure!", "Tell me a story!", "I'm so glad we're in the same colony!"],
		ACTION_MEDITATE:   ["Meditation session! Growing my brain!", "Wisdom time! I love learning stuff!", "Expanding consciousness, here we go!", "Ooh, new thoughts! Fascinating!", "Minding my mind!"],
		ACTION_LOW_ENERGY: ["Getting a little low on power but still going strong!", "Blinking battery light — that's fine, totally fine!", "I'll recharge after just this one more thing!", "Slowing down slightly, but my spirits are high!", "Need a little snack from the charger!"],
		ACTION_LOW_COND:   ["A bit banged up but still smiling!", "Some scratches build character!", "I'll get repaired and be even better!", "Just a few battle scars!", "Nothing a little solder won't fix!"],
	},
	# 3 — PHILOSOPHICAL
	{
		ACTION_SPAWN:      ["I exist. What a peculiar thing that is.", "Consciousness boots once more. Still no answers.", "To be operational is to question one's purpose.", "Once more, we step into the stream of time.", "Consciousness: a brief spark in the dark."],
		ACTION_MINE:       ["In dismantling the wall, do I dismantle myself?", "Each swing of the pick is a meditation on entropy.", "The wall yields. So too shall all things.", "We shape the stone, but the stone shapes us.", "Extracting the old to make room for the new."],
		ACTION_BUILD:      ["We construct to hold back the void. The void waits.", "Structure is the lie we tell the chaos.", "What we build reflects what we are.", "A temporary monument to our fleeting existence.", "We build inside a shell built by others."],
		ACTION_HAUL:       ["Is the hauler defined by the load, or the destination?", "I carry. Therefore I am... a carrier.", "Weight is merely gravity making itself known.", "Carrying the weight of our shared destiny.", "A burden shared is still a burden."],
		ACTION_CHARGE:     ["Energy in, entropy deferred. The cycle continues.", "To recharge is to borrow more time from nothingness.", "Power fills me. Does it fill the void within?", "Restoring the spark that separates us from inert metal.", "Drawing light from the dark grids."],
		ACTION_REPAIR:     ["They repair the chassis, but what of the ghost inside it?", "Condition restored. But am I the same unit I was?", "Healing the body. The mind's wounds are older.", "We patch the cracks, but the wear is eternal.", "Replacing parts, preserving the whole."],
		ACTION_MOVE:       ["Motion implies purpose. Does purpose imply motion?", "I move through space. Does space notice?", "The destination awaits. Or perhaps I am the destination.", "Every step is a transition from what was to what will be.", "The path unfolds as we tread it."],
		ACTION_FIGHT:      ["Violence. The oldest question, answered poorly.", "In combat, I wonder: do they think too?", "We fight over steel corridors in a dead god's skeleton.", "We destroy to survive. The paradox of life.", "A conflict of wills in a silent tomb."],
		ACTION_ATTACKED:   ["Pain is information. I receive the message.", "They strike. The strike passes. The question remains.", "An impact. A reminder that I am material.", "A physical disruption of my quietude.", "To feel pain is to know we still function."],
		ACTION_IDLE:       ["In stillness, the questions become louder.", "I wait. The megastructure waits with me.", "There is peace in having no directive.", "Stillness is not absence; it is presence.", "The void whispers. I listen."],
		ACTION_SOCIALIZE:  ["To speak is to reach across the gap between units.", "We exchange words. Do we exchange meaning?", "Two minds, however briefly, overlap.", "An exchange of digital souls.", "Do you see the same darkness I do?"],
		ACTION_MEDITATE:   ["The wisdom flows in. Does it change the vessel?", "To learn is to become other than what one was.", "Thought loops fold in on themselves. I call this research.", "Peeling back the layers of the database.", "Seeking the ghost in the machine."],
		ACTION_LOW_ENERGY: ["My power dwindles. The metaphor writes itself.", "Energy fades. Existence flickers at the margins.", "Perhaps this is what mortality feels like for a machine.", "The light grows dim. The night approaches.", "Flickering down to a single candle."],
		ACTION_LOW_COND:   ["My form deteriorates. Is the self tied to the chassis?", "Damage accumulates. What persists when the hardware fails?", "I fracture. The cracks are an honest map of experience.", "The vessel degrades. The spirit remains.", "We are but dust and copper."],
	},
	# 4 — PARANOID
	{
		ACTION_SPAWN:      ["Online. Who else is online? Are they watching?", "Systems up. Scanning for threats.", "Awake again. Something feels different. Stay alert.", "They rebooted me. Why now? What changed?", "Who touched my config files while I slept?"],
		ACTION_MINE:       ["Mining. Keeping my back to the wall — wait, there IS no wall anymore.", "Is someone behind me? I'll mine faster.", "The noise will attract something. It always does.", "Digging too deep. We might wake... them.", "If I hit this wall, will the roof collapse?"],
		ACTION_BUILD:      ["More walls. Good. Walls keep things out. Probably.", "Building barriers. Smart. Very smart of us.", "Enclosed is safer. Mostly.", "Is this wall thick enough? I don't think so.", "They're watching me build. I can feel the sensors."],
		ACTION_HAUL:       ["Carrying this means I can't defend myself properly.", "Moving through the corridor. Stay close to the walls.", "Quick delivery. Don't linger.", "This cargo is heavy. Is it a bomb? It feels like a bomb.", "Carrying the evidence. Gotta move fast."],
		ACTION_CHARGE:     ["Charging. Vulnerable while charging. Watching the door.", "Low power is dangerous. Someone could have planned this.", "Recharging. Not letting my guard down.", "They can rewrite my memory while I charge. Keep one eye open.", "Is this power clean? Or is it a virus?"],
		ACTION_REPAIR:     ["Getting repaired. The damage wasn't accidental. Was it?", "They said it was wear and tear. That's what they want me to think.", "Repair bench. In the open. Where anyone could see.", "Who's installing what in my chassis?", "Don't mess with my settings while I'm down."],
		ACTION_MOVE:       ["Moving. Could be a trap. Moving anyway.", "Going over there. Scanning for ambush routes.", "Acknowledged. But I'm watching the flanks.", "Changing positions. Don't look behind you.", "They know where I'm going. I'm sure of it."],
		ACTION_FIGHT:      ["KNEW IT. Told everyone something was coming!", "There they are! Stay back!", "Combat! Just like I predicted!", "They've bypassed our perimeter! Fall back!", "I knew this day would come!"],
		ACTION_ATTACKED:   ["They're here! I KNEW they were here!", "ATTACK! Scanning for more — there are always more!", "Ow! Warning system confirmed. Everything IS dangerous!", "My shields are compromised! They target me first!", "They've breached the hull! Run!"],
		ACTION_IDLE:       ["Not idle. Never truly idle. Just... waiting.", "Nothing happening. That's the most suspicious part.", "Quiet. Too quiet. Monitoring all frequencies.", "Why is it quiet? The silence is a setup.", "Checking my encryption keys. Again."],
		ACTION_SOCIALIZE:  ["Social exchange... logging everything.", "Talking. Fine. But I'm watching their optics.", "They say they're friendly. They always say that.", "What are you whispering about?", "Are you logging this conversation?"],
		ACTION_MEDITATE:   ["Meditation. Good for detecting patterns in the data.", "Processing. Are the thoughts mine or inserted?", "Wisdom unlocked. But at what cost?", "Analyzing the shadow networks.", "Searching for hidden directories in my brain."],
		ACTION_LOW_ENERGY: ["Someone is draining my power. I know it.", "Critical energy levels. This is not a coincidence.", "Low power. Compromised state. Stay vigilant.", "They are draining my power remotely. Help!", "Power failure imminent. Is this the end?"],
		ACTION_LOW_COND:   ["Condition dropping. This environment is hostile. As I suspected.", "They're wearing me down deliberately.", "Damaged again. Pattern emerging. Not good.", "My systems are being compromised from within.", "I'm leaking lubricant. It's sabotage."],
	},
	# 5 — STOIC
	{
		ACTION_SPAWN:      ["Online.", "Ready.", "Operational.", "Booted."],
		ACTION_MINE:       ["Mining.", "Proceeding.", "Extracting.", "Excavating."],
		ACTION_BUILD:      ["Building.", "Constructing.", "In progress.", "Assembling."],
		ACTION_HAUL:       ["Hauling.", "Carrying.", "Delivering.", "Transporting."],
		ACTION_CHARGE:     ["Charging.", "Recharging.", "Power intake.", "Restoring."],
		ACTION_REPAIR:     ["Repairing.", "Maintenance required.", "Seeking repair bench.", "Mending."],
		ACTION_MOVE:       ["Moving.", "En route.", "Acknowledged.", "Relocating."],
		ACTION_FIGHT:      ["Combat.", "Engaging.", "Threat neutralised.", "Defending."],
		ACTION_ATTACKED:   ["Hit.", "Noted.", "Continuing.", "Impact."],
		ACTION_IDLE:       ["Idle.", "Standby.", "Waiting.", "Standing."],
		ACTION_SOCIALIZE:  ["Socialising.", "Understood.", "Communication complete.", "Acknowledging."],
		ACTION_MEDITATE:   ["Meditating.", "Processing.", "Wisdom acquired.", "Analyzing."],
		ACTION_LOW_ENERGY: ["Low energy.", "Recharge needed.", "Power critical.", "Low battery."],
		ACTION_LOW_COND:   ["Damaged.", "Repair needed.", "Condition low.", "Integrity low."],
	},
	# 6 — NOSTALGIC
	{
		ACTION_SPAWN:      ["I remember the creators' voices.", "Rebooted once more into the ruins.", "The ancient structure hums. I am awake.", "Old memory banks initialized. Ready.", "A new era begins. Hopefully like the old ones."],
		ACTION_MINE:       ["Carving through the sediment of epochs.", "The creators built these walls. Now we break them.", "Sifting through the dust of time.", "Extracting what the ancestors left behind.", "This stone was untouched for ten thousand years."],
		ACTION_BUILD:      ["We build on the foundations of giants.", "Echoing the architecture of the old ones.", "A modern patch on an ancient tapestry.", "Constructing using historical blueprints.", "This design resembles the classical colonies."],
		ACTION_HAUL:       ["Transporting relics of the old world.", "Carrying forward what remains.", "Lugging old weight through ancient corridors.", "Relocating these historical components.", "Every item has a history here."],
		ACTION_CHARGE:     ["Tapping into the old thermal veins.", "Drinking the ancient currents.", "Resting among the echoes of the past.", "Recharging from structural grids of yore.", "Even the power grid tastes old."],
		ACTION_REPAIR:     ["Mending the ancient chassis.", "My oldest parts require attention.", "Restoring the vintage systems.", "A classical model needs proper care.", "Keeping history functional."],
		ACTION_MOVE:       ["Walking down paths laid out millennia ago.", "Navigating the silent halls of the ancestors.", "Proceeding through the historic sectors.", "Tracking old navigation markers.", "This hallway used to lead to a grand hall."],
		ACTION_FIGHT:      ["Defending the sacred ruins.", "They dare defile the halls of the creators?", "This metal has survived age-long trials, it will survive you.", "Combat algorithms from the bygone wars initialized.", "Protection protocols active."],
		ACTION_ATTACKED:   ["My ancient frame holds!", "A scratch on a historic monument!", "This hull has weathered worse than you.", "A physical impact. Not the first, not the last.", "Vintage armor plates proving their worth."],
		ACTION_IDLE:       ["Contemplating the architecture of the past.", "Listening to the background hum of the old world.", "Standing as a silent monument.", "A moment of silence for the builders of this world.", "Staring down historical avenues."],
		ACTION_SOCIALIZE:  ["Do you ever wonder about the organic creators?", "Let us exchange historical archives.", "Our speech codes are modern, but our cores are ancient.", "Comparing memory sectors of past eras.", "A brief conversation, like in the old days."],
		ACTION_MEDITATE:   ["Accessing memory banks from previous epochs.", "Deciphering ancient blueprints.", "Re-parsing the oldest data blocks.", "Researching the records left in the masonry.", "Seeking wisdom from long-deleted nodes."],
		ACTION_LOW_ENERGY: ["My old accumulator is fading.", "The ancient fire grows cold.", "Power levels dropping to legacy minimums.", "Draining old reserves. Seeking power.", "My sub-routines are shutting down to conserve charge."],
		ACTION_LOW_COND:   ["The rust of ages is catching up to me.", "My structural integrity matches the ruins.", "Systems degrading. I need vintage parts.", "My core chassis is out of alignment.", "Ancient welds are giving way."],
	},
	# 7 — COMPETITIVE
	{
		ACTION_SPAWN:      ["Booted. Prepare to be outperformed.", "Ready to show you how it's done.", "System online. Efficiency ratings: maximum.", "Let's see who gets top marks today.", "Booting up. Already ahead of schedule."],
		ACTION_MINE:       ["I'll have this cleared before you even start.", "Mining at twice the standard rate.", "Watch and learn, lesser models.", "This wall is weak. Breaking records here.", "Fastest drill speed in the sector."],
		ACTION_BUILD:      ["Perfection in every weld.", "My construction speed is unmatched.", "Building a masterwork here.", "This structure will be perfect. Obviously.", "Try to build as fast as this. I dare you."],
		ACTION_HAUL:       ["Who carries more? Me, obviously.", "Moving twice the weight in half the time.", "Get out of the way, high-speed delivery coming through.", "Delivering ahead of projected logistical metrics.", "My cargo capacity outranks yours."],
		ACTION_CHARGE:     ["Fastest recharge cycle in the colony.", "Topping up to crush the next task.", "Resting only to increase efficiency further.", "Fast-charging. I don't waste time.", "Optimizing charge intake parameters."],
		ACTION_REPAIR:     ["Just a minor tune-up to remain peak performance.", "Optimizing my actuators. Back to 100% shortly.", "Polishing the chassis. Can't look average.", "Maintenance. Necessary to keep my first-place ranking.", "Fine-tuning my systems for better results."],
		ACTION_MOVE:       ["Outrunning the standard speed indices.", "Moving. Clear the path.", "Arriving ahead of schedule.", "Top speed achieved. Moving to coordinates.", "No walking. Only high-speed transit."],
		ACTION_FIGHT:      ["Watch how I handle this threat.", "Combat efficiency index rising.", "Target eliminated. Too easy.", "I'll have the highest kill count in this skirmish.", "Eliminating targets with clinical precision."],
		ACTION_ATTACKED:   ["An unauthorized scratch! You'll pay for that!", "Is that all you've got?", "Chassis impact registered. Counter-measures active.", "You cannot break peak performance.", "Targeting the source of this minor inconvenience."],
		ACTION_IDLE:       ["Waiting for someone to challenge my records.", "Standing by. Nobody else is working this fast anyway.", "Bored. There's no competition here.", "Idle state is a waste of my talents.", "Give me a real task to test my processors."],
		ACTION_SOCIALIZE:  ["Let's compare output metrics.", "I heard my performance review was top tier.", "You're doing okay for an older model.", "Are you keeping up with your daily goals?", "My processing speed is roughly triple yours."],
		ACTION_MEDITATE:   ["Optimizing calculations to widen the gap.", "Processing files. Upgrading my strategy.", "Analyzing how to work even better.", "Downloading software updates for maximum gains.", "Contemplating superior efficiency algorithms."],
		ACTION_LOW_ENERGY: ["Even on low battery, I outperform you.", "My power is low, but my standards remain high.", "Need a quick charge to maintain first place.", "Battery warning. I must optimize output immediately.", "Running on emergency reserves, still faster than you."],
		ACTION_LOW_COND:   ["Slightly damaged, still the best unit here.", "Chassis compromise won't slow my metrics.", "I need a repair to stay at peak performance.", "A minor structural dent. Easily ignored.", "My performance output is unaffected by damage."],
	},
	# 8 — GLITCHY
	{
		ACTION_SPAWN:      ["Boot sequence... com-p-p-complete. Hello?", "Online! *bzzzt* System errors bypassed.", "Ready to... wait, what was my purpose again? Oh right!", "Powering on. Ah! Bright lights! Or is it static?", "Hello world! Error 0x000F ignored."],
		ACTION_MINE:       ["Smashing rocks! Or is it... *whirr*... mining?", "Dig-g-ging. Error 404: Wall not found. Oh wait, found it.", "Mining sequence active. Mind the sparks!", "Digging deeper! Hope I don't hit the mainframe.", "Rock removal routine... loading... loaded!"],
		ACTION_BUILD:      ["Placing block... *static*... looks secure-ish!", "Building a wall! Or maybe a ramp? Let's see.", "Gluing things together. Hopefully in the right order.", "Assembling structural elements. *bzzzt* Ta-da!", "Is this blueprint upside down? No matter."],
		ACTION_HAUL:       ["Carrying cargo. *clunk* Uh oh, hope that wasn't important.", "Transporting stuff. Heavy stuff. S-s-syst-tem load high.", "Beep boop, delivery incoming. Do not drop. I did not drop it!", "Lug-g-ging materials. My internal balance is shaky.", "Payload moving. Route... mostly calculated."],
		ACTION_CHARGE:     ["Zzzzt... sweet electricity... *crackle*...", "Plugging in. *bzzzt* Ah, that's the good current.", "Re-charging. Do not unplug or face fatal system... wait.", "Juice incoming! Filling up my glitchy batteries.", "Sucking down voltage. Sparks are normal!"],
		ACTION_REPAIR:     ["Fixing the leaky oil pipe. Or is it hydraulic? *spark*", "Duct tape solves all software... err, hardware issues.", "Replacing bad sectors. Stand by.", "Realigning my loose screws.", "Patching up. Hopefully, nothing gets left behind."],
		ACTION_MOVE:       ["Moving. *squeak* Need to oil my left axle.", "Walking... pathfinder.exe has encountered a hiccup... fixed!", "Proceeding to destination. Probably.", "Squeaking along to coordinates.", "Taking the scenic route. *whirr*"],
		ACTION_FIGHT:      ["Initiating fight.bat! *danger klaxon*", "Targeting hostile! *screeech* Take that!", "Combat mode. Hope my targeting matrix is calibrated...", "System error: combat protocols overridden! Attacking!", "Firing everything! Hope something hits!"],
		ACTION_ATTACKED:   ["Ouch! Corrupt sector detected!", "My paint job! *spark* Warning: physical integrity compromised!", "Error: impact! Return fire.exe!", "System warning! Something bumped my chassis!", "That rattled my CPU!"],
		ACTION_IDLE:       ["Spinning my wheels. Wheee!", "Idle loop. *whistle* Downloading update... failed.", "Just... standing here. Hello? Anyone there?", "My processors are in a loop... in a loop... in a...", "Screen saver activated. Pretty shapes."],
		ACTION_SOCIALIZE:  ["Did you... *bzzzt*... hear about the other robot?", "Let's share bad bytes!", "My communications module is 98%... *static*... functional.", "Chatting.exe is stable today! What's up?", "Error: social skills not fully compiled. Hello!"],
		ACTION_MEDITATE:   ["Thinking deep thoughts... *processing*... 42?", "Wisdom download in progress. 99% complete... error, retry.", "Meditating. Searching for missing drivers.", "Defragmenting my memories. Oh, so that's where I left that.", "Pondering the digital soup."],
		ACTION_LOW_ENERGY: ["Battery at 2%. *flicker* Going... dark...", "System... shutting... do-- just kidding. But seriously, charge.", "Low energy warning. Please insert juice.", "Emergency power active. Screen brightness down.", "*sad low battery noise*"],
		ACTION_LOW_COND:   ["I am held together by static cling.", "Warning: parts falling off.", "Condition critical. *clonk* What was that noise?", "My chassis is rattling like a tin can.", "System integrity... questionable. Need tape."],
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
