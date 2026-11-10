class_name SaveFile
extends RefCounted
## The one on-disk container for game state: a save is not a text file.
##
## Every save this game writes - the warband, the purse, the player's ledger and
## the campaign index - goes through this class. The bytes are:
##
##   "BCSV" | format u8 | nonce 16 | ciphertext size u32 | ciphertext | tag 32
##
## The payload is the dictionary the game used to write as JSON, serialised with
## `var_to_bytes` (a binary Variant blob: string keys, floats, arrays, and nothing
## else - never an Object). It is enciphered with a **HMAC-SHA256 counter-mode
## keystream**: block `n` of the keystream is `HMAC(key, nonce || u32(n))`, and the
## payload is XORed with the concatenation. That is CTR mode built on the only
## primitive this engine exposes cleanly (`Crypto.hmac_digest`), so there is no
## padding to get wrong and the ciphertext is exactly as long as the payload. The
## 32-byte tail is `HMAC(mac_key, nonce || ciphertext)`.
##
## Reading verifies the tag **before** touching the cipher, so a file that changed
## since the game wrote it is refused whole instead of half-honoured: no key, no
## forge, no run counter, no purse, no campaign.
##
## ## What this is, and what it is not
##
## This is a **sealed container with integrity**, not secrecy. Both keys ship
## inside the binary, so somebody who unpacks the executable (or reads this file)
## can decrypt and re-seal a save - the keystream stops a text editor, not a
## reverse engineer. What it *does* buy, and why it is worth the bytes:
##
##   * No save is editable in Notepad, a hex editor, a JSON tool or a trainer that
##     rewrites plain values: the payload is opaque and the tag catches every edit
##     that is not a full re-seal with the game's own keys.
##   * An edit that skips the tag is *detectable*: `inspect()` answers
##     `problem = "tampered"`, and the reader refuses the file rather than loading
##     whatever parsed.
##   * Bit-rot and truncation are caught by the same check, so a damaged file is
##     refused with a reason instead of importing nonsense.
##
## A game that wanted real anti-cheat would keep the numbers it cares about on a
## server it owns. Blood Champions has no server: a single-player campaign, and a
## co-op host whose guests trust the host's word. Against that, this is the honest
## ceiling - it raises the cost of cheating from "open the file" to "reverse the
## binary", and it turns an edited file into a refusal instead of a win.
##
## ## Old saves
##
## A file whose first four bytes are not the magic is read as the plain JSON the
## build wrote before this class existed, so a save from an older build still
## opens; the next write seals it. Nothing reads the legacy form after that.
##
## The file names kept their `.json` tails (`warband_state.json` and the rest).
## The name is history and the ledger's paths are built from it; the container is
## what decides the format, never the extension.

## The container's first four bytes. A file that does not start with them is the
## legacy plain-JSON save.
const MAGIC := "BCSV"
## The container version. A newer one is refused (`problem = "newer"`) rather than
## read as if it were this one.
const FORMAT := 1
## magic (4) + format (1).
const HEADER := 5
const NONCE_BYTES := 16
const TAG_BYTES := 32
const SIZE_BYTES := 4
## One keystream block: `HMAC-SHA256` answers 32 bytes.
const BLOCK_BYTES := 32

## What `inspect()` says the file was.
const SEALED := "sealed"
const PLAIN := "plain"

## The keystream key and the tag key, hex. Rotating either needs a `FORMAT` bump
## and a reader for the older format, or every save on every machine stops opening.
const KEY_HEX := "91c725eee6b4f53d5cf15d4f61a81c5a4530e8845dd7a3957baada96fe684ec4"
const MAC_KEY_HEX := "5365aa64bfc7819a4106fff0db27a7cfb07e47d1bfc390d413ba4a4cf82a966a"

static var _aes := PackedByteArray()
static var _hmac := PackedByteArray()


## Write `data` to `path` as a sealed save. False when the file could not be
## opened; a save that cannot be written must never be silently dropped.
static func write(path: String, data: Dictionary) -> bool:
	if path.is_empty():
		return false
	var crypto := Crypto.new()
	var nonce := crypto.generate_random_bytes(NONCE_BYTES)
	var cipher := seal(var_to_bytes(data), nonce)
	if cipher.is_empty():
		return false
	var tag := crypto.hmac_digest(HashingContext.HASH_SHA256, _mac_key(), nonce + cipher)
	var folder := path.get_base_dir()
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(MAGIC.to_utf8_buffer())
	file.store_8(FORMAT)
	file.store_buffer(nonce)
	file.store_32(cipher.size())
	file.store_buffer(cipher)
	file.store_buffer(tag)
	file.close()
	return true


## The file and what it is, without adopting it: `{ok, data, format, problem}`.
## `problem` is `""` when `ok`; otherwise `"missing"`, `"unreadable"`,
## `"truncated"`, `"corrupt"`, `"newer"` or `"tampered"` - the last being a file
## whose bytes changed after the game sealed it.
static func inspect(path: String) -> Dictionary:
	var out := {"ok": false, "data": {}, "format": "", "problem": "missing"}
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		out["problem"] = "unreadable"
		return out
	var raw := file.get_buffer(file.get_length())
	file.close()
	if raw.size() >= HEADER and raw.slice(0, 4).get_string_from_utf8() == MAGIC:
		return _open_sealed(raw, out)
	# Legacy: the plain JSON a build before this class wrote.
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if parsed is Dictionary:
		out["ok"] = true
		out["data"] = parsed
		out["format"] = PLAIN
		out["problem"] = ""
		return out
	out["problem"] = "unreadable"
	return out


## Just the payload: `{}` for anything this build will not open. Callers that need
## to know *why* a file was refused use `inspect()`.
static func read(path: String) -> Dictionary:
	return inspect(path).get("data", {})


static func exists(path: String) -> bool:
	return not path.is_empty() and FileAccess.file_exists(path)


## The cipher: XOR `data` with the HMAC counter-mode keystream for `nonce`. The
## same call seals and opens, so the two can never disagree about the stream.
static func seal(data: PackedByteArray, nonce: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	if data.is_empty():
		return out
	out.resize(data.size())
	var crypto := Crypto.new()
	var key := _key()
	var blocks := int(ceil(float(data.size()) / float(BLOCK_BYTES)))
	for block in blocks:
		var stream := crypto.hmac_digest(HashingContext.HASH_SHA256, key,
			nonce + _counter_bytes(block))
		var base := block * BLOCK_BYTES
		var take := mini(BLOCK_BYTES, data.size() - base)
		for offset in take:
			out[base + offset] = data[base + offset] ^ stream[offset]
	return out


## One block index as four big-endian bytes, so the counter is fixed width and
## two different blocks can never share a keystream.
static func _counter_bytes(block: int) -> PackedByteArray:
	return PackedByteArray([(block >> 24) & 0xFF, (block >> 16) & 0xFF,
		(block >> 8) & 0xFF, block & 0xFF])


## The sealed branch of `inspect`: check the frame, verify the tag, then decrypt.
static func _open_sealed(raw: PackedByteArray, out: Dictionary) -> Dictionary:
	if int(raw[4]) != FORMAT:
		out["problem"] = "newer"
		return out
	var body := HEADER + NONCE_BYTES + SIZE_BYTES
	if raw.size() < body + TAG_BYTES:
		out["problem"] = "truncated"
		return out
	var nonce := raw.slice(HEADER, HEADER + NONCE_BYTES)
	var size := int(raw.decode_u32(HEADER + NONCE_BYTES))
	if size <= 0 or body + size + TAG_BYTES != raw.size():
		out["problem"] = "corrupt"
		return out
	var cipher := raw.slice(body, body + size)
	var tag := raw.slice(body + size, raw.size())
	# The tag first: a file that changed since the game wrote it never reaches the
	# cipher, so an edited payload cannot even be decrypted into nonsense.
	var wanted := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _mac_key(),
		nonce + cipher)
	if wanted != tag:
		out["problem"] = "tampered"
		return out
	var data: Variant = bytes_to_var(seal(cipher, nonce))
	if not data is Dictionary:
		out["problem"] = "corrupt"
		return out
	out["ok"] = true
	out["data"] = data
	out["format"] = SEALED
	out["problem"] = ""
	return out


static func _key() -> PackedByteArray:
	if _aes.is_empty():
		_aes = KEY_HEX.hex_decode()
	return _aes


static func _mac_key() -> PackedByteArray:
	if _hmac.is_empty():
		_hmac = MAC_KEY_HEX.hex_decode()
	return _hmac
