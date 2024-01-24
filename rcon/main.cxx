#include <arpa/inet.h>
#include <array>
#include <cstdint>
#include <cstring>
#include <errno.h>
#include <iomanip>
#include <iostream>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <string>
#include <sys/socket.h>
#include <sys/types.h>
#include <tuple>
#include <unistd.h>
#include <unordered_set>
#include <vector>

// https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
// https://github.com/Jaskowicz1/rconpp/wiki/The-Source-RCON-Protocol

/* clang-format off

// Total max packet size = 4100 bytes
struct Packet
{
	uint32_t size;       // max value = 4096
	uint32_t id;         // -4
	uint32_t type;       // -4
	uint8_t body[4087];  // -4087 (max)
	uint8_t null;        // -1
	                     // = 0
};

clang-format on */

uint16_t constexpr DEFAULT_RCON_PORT = 27015;
int constexpr TOTAL_PACKET_SIZE = 4100;

bool test();
auto split_hoststr(std::string const& hoststr) -> std::tuple<std::string, uint16_t>;
auto get_password(int timeout_ms = 5000) -> std::string;
auto to_little_endian(uint32_t value) -> std::array<uint8_t, sizeof(uint32_t)>;
auto from_little_endian(std::array<uint8_t, sizeof(uint32_t)> const& bytes) -> uint32_t;
bool is_big_endian();

#define stream_errno(errno) strerrorname_np(errno) << " (" << errno << "): " << strerror(errno) << '\n'

enum class PacketType
{
	SERVERDATA_AUTH,
	SERVERDATA_AUTH_RESPONSE,
	SERVERDATA_EXECCOMMAND,
	SERVERDATA_RESPONSE_VALUE
};

auto constexpr from(PacketType type) -> uint32_t
{
	switch (type) {
	case PacketType::SERVERDATA_AUTH: return 3;
	case PacketType::SERVERDATA_AUTH_RESPONSE:  // AUTH_RESPONSE and EXECCOMMAND are both 2
	case PacketType::SERVERDATA_EXECCOMMAND: return 2;
	case PacketType::SERVERDATA_RESPONSE_VALUE: return 0;
	}
	return 0;
}

class Packet
{
	friend class RconConnection;

	uint32_t _size;
	uint32_t _id;
	uint32_t _type;
	std::vector<uint8_t> _body;

public:
	Packet(uint32_t id)
	    : _size {}
	    , _id {id}
	    , _type {}
	    , _body {}
	{}

	auto size() const -> uint32_t
	{
		return _size;
	}

	auto id() const -> uint32_t
	{
		return _id;
	}

	void set_type(PacketType type)
	{
		_type = from(type);
	}

	void set_body(std::string const& body)
	{
		_body = std::vector<uint8_t>(body.begin(), body.end());
		update_size();
	}

	auto to_byte_buffer() const -> std::vector<uint8_t>
	{
		static auto constexpr null_terminators = std::array<uint8_t, 2> {0, 0};

		std::vector<uint8_t> buffer {};
		buffer.reserve(_size + sizeof(_size));
		static_assert(sizeof(_size) == 4);

		auto size = to_little_endian(_size);
		auto id = to_little_endian(_id);
		auto type = to_little_endian(_type);

		buffer.insert(buffer.end(), size.begin(), size.end());
		buffer.insert(buffer.end(), id.begin(), id.end());
		buffer.insert(buffer.end(), type.begin(), type.end());
		buffer.insert(buffer.end(), _body.begin(), _body.end());
		buffer.insert(buffer.end(), null_terminators.begin(), null_terminators.end());

		return buffer;
	}

private:
	void update_size()
	{
		// _size itself is not included in calculating the value of _size
		auto constexpr offset = sizeof(_id)           // 32-bit integer
		                      + sizeof(_type)         // 32-bit integer
		                      + sizeof(uint8_t) * 2;  // two bytes of null terminators
		static_assert(offset == 10);
		_size = _body.size() + offset;
	}
};

class IdGenerator
{
	std::unordered_set<int> _ids {};

public:
	int generate()
	{
		int id = 0;
		while (_ids.find(id) != _ids.end()) {
			id++;
		}
		_ids.insert(id);
		return id;
	}

	void release(int id)
	{
		_ids.erase(id);
	}
};

class RconConnection
{
	std::string _hostname;
	uint16_t _port;
	int _sockfd;
	IdGenerator _id;
	std::array<uint8_t, TOTAL_PACKET_SIZE> _buffer;

public:
	RconConnection(std::string const& hoststr)
	    : _hostname {}
	    , _port {}
	    , _sockfd {-1}
	    , _id {}
	{
		std::tie(_hostname, _port) = split_hoststr(hoststr);
	}

	bool authenticate(std::string const& password, int timeout_ms = 5000)
	{
		auto id = _id.generate();
		Packet packet(id);
		packet.set_type(PacketType::SERVERDATA_AUTH);
		packet.set_body(password);

		bool success = true;

		if (!send(packet)) {
			success = false;
		}

		// Received packet should be SERVERDATA_AUTH_RESPONSE with id == sent id | -1 on failure
		if (success && !recv(packet, timeout_ms)) {
			success = false;
		}

		if (success && packet._type != from(PacketType::SERVERDATA_AUTH_RESPONSE)) {
			std::cout << "Expected packet type SERVERDATA_AUTH_RESPONSE (" << from(PacketType::SERVERDATA_AUTH_RESPONSE)
			          << ") but got " << packet._type << '\n';
			success = false;
		}

		if (success && packet.id() != id) {
			success = false;
		}

		_id.release(id);
		return success;
	}

	bool command(std::string const& command, int timeout_ms = 5000)
	{
		auto id = _id.generate();
		Packet packet(id);
		packet.set_type(PacketType::SERVERDATA_EXECCOMMAND);
		packet.set_body(command);

		bool success = true;

		if (!send(packet)) {
			success = false;
		}

		// Received packet should be SERVERDATA_RESPONSE_VALUE with id == sent id
		if (success && !recv(packet, timeout_ms)) {
			success = false;
		}

		if (success && packet._type != from(PacketType::SERVERDATA_RESPONSE_VALUE)) {
			std::cout << "Expected packet type SERVERDATA_RESPONSE_VALUE ("
			          << from(PacketType::SERVERDATA_RESPONSE_VALUE) << ") but got " << packet._type << '\n';
			success = false;
		}

		if (success && packet.id() != id) {
			std::cout << "Expected packet id " << id << " but got " << packet.id() << '\n';
			success = false;
		}

		// TODO: Handle multi-packet responses

		std::string response {packet._body.begin(), packet._body.end()};
		std::cout << response << '\n';

		_id.release(id);
		return success;
	}

	bool send(Packet const& packet)
	{
		if (_sockfd < 0 && !connect_to_server()) {
			return false;
		}

		auto buffer = packet.to_byte_buffer();
		if (::send(_sockfd, buffer.data(), buffer.size(), 0) < 0) {
			std::cout << "Error sending packet: " << stream_errno(errno);
			return false;
		}
		return true;
	}

	bool recv(Packet& packet, int timeout_ms = 5000)
	{
		if (_sockfd < 0 && !connect_to_server()) {
			return false;
		}

		Packet out_packet(0);
		pollfd fd {};
		fd.fd = _sockfd;
		fd.events = POLLIN;

		int result = poll(&fd, 1, timeout_ms);

		if (result > 0 && (fd.revents & POLLIN)) {
			int bytes_received = ::recv(_sockfd, _buffer.data(), _buffer.size(), 0);

			if (bytes_received < 0) {
				std::cout << "Error receiving packet: " << stream_errno(errno);
				return false;
			}

			out_packet._size = from_little_endian({_buffer[0], _buffer[1], _buffer[2], _buffer[3]});
			out_packet._id = from_little_endian({_buffer[4], _buffer[5], _buffer[6], _buffer[7]});
			out_packet._type = from_little_endian({_buffer[8], _buffer[9], _buffer[10], _buffer[11]});
			// Skip last two bytes (null terminators)
			out_packet._body = std::vector<uint8_t>(_buffer.begin() + 12, _buffer.begin() + bytes_received - 2);
		}
		else if (result == 0) {
			std::cout << "Timed out waiting for packet\n";
			return false;
		}
		else {
			std::cout << "Error waiting for packet: " << stream_errno(errno);
			return false;
		}

		packet = out_packet;
		return true;
	}

private:
	bool connect_to_server()
	{
		auto info = resolve_hostname(_hostname);

		// char buf[INET_ADDRSTRLEN] {};
		// inet_ntop(info.sin_family, &info.sin_addr, buf, sizeof(buf));
		// std::cout << "Resolved hostname " << _hostname << " to IP address " << buf << '\n';

		int sockfd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);

		if (sockfd < 0) {
			std::cout << "Error creating socket: " << stream_errno(errno);
			return false;
		}

		sockaddr_in serv_addr {};
		serv_addr.sin_family = AF_INET;
		serv_addr.sin_port = htons(_port);

		if (connect(sockfd, (sockaddr*) &serv_addr, sizeof(serv_addr)) < 0) {
			std::cout << "Error connecting to server: " << stream_errno(errno);
			return false;
		}

		_sockfd = sockfd;
		return true;
	}

	auto resolve_hostname(std::string const& hostname) -> sockaddr_in
	{
		addrinfo hints {};
		addrinfo* result = nullptr;

		hints.ai_family = AF_INET;
		hints.ai_socktype = SOCK_STREAM;

		int status = getaddrinfo(hostname.c_str(), nullptr, &hints, &result);

		if (status != 0) {
			std::cout << "Error resolving hostname: " << gai_strerror(status) << '\n';
			return {};
		}

		if (result->ai_next) {
			std::cout << "Warning: hostname resolved to multiple IP addresses!\n";
		}

		sockaddr_in addr {};
		std::memcpy(&addr, result->ai_addr, sizeof(addr));
		freeaddrinfo(result);

		return addr;
	}
};

// g++ main.cxx && ./a.out
int main(int argc, char const* argv[])
{
	std::string filename = argv[0];
	std::string basename = filename.substr(filename.find_last_of("\\/") + 1);

	if (argc == 2 && std::string {argv[1]} == "test") {
		return test() ? 0 : 1;
	};

	if (argc < 2) {
		std::cout << "RCON client " << basename << "\n\n"
		          << "Usage: " << basename << " host[:port] [command] <<< rcon_password\n"
		          << "   or: echo rcon_password | " << basename << " host[:port] [command]\n"
		          << "   or: cat file_with_rcon_password | " << basename << " host[:port] [command]\n\n"
		          << "If a command is not provided, the client will print whether or not it can connect to the "
		             "server.\n";
		return 1;
	}

	RconConnection rcon {argv[1]};
	auto password = get_password();

	if (password.empty()) {
		return 1;
	}

	std::cout << "Authentication... ";

	if (rcon.authenticate(password)) {
		std::cout << "success\n";
	}
	else {
		std::cout << "failed!\n";
		return 1;
	}

	if (argc > 2) {
		std::string command {argv[2]};
		for (int i = 3; i < argc; i++) {
			command += ' ';
			command += argv[i];
		}
		std::cout << "Sending command \"" << command << "\"...\n";
		return rcon.command(command) ? 0 : 1;
	}

	return 0;
}

auto split_hoststr(std::string const& hoststr) -> std::tuple<std::string, uint16_t>
{
	std::string host {};
	uint16_t port {};

	auto colon = hoststr.find_last_of(':');

	if (colon == std::string::npos) {
		host = hoststr;
		port = DEFAULT_RCON_PORT;
	}
	else {
		host = hoststr.substr(0, colon);
		if (host.empty()) {
			host = "localhost";
		}
		try {
			port = std::stoi(hoststr.substr(colon + 1));
		} catch (std::invalid_argument const& e) {
			port = DEFAULT_RCON_PORT;
		}
	}

	return {host, port};
}

auto get_password(int timeout_ms) -> std::string
{
	std::string password {};

	struct pollfd fd
	{};

	fd.fd = STDIN_FILENO;
	fd.events = POLLIN;

	int result = poll(&fd, 1, timeout_ms);

	if (result > 0 && (fd.revents & POLLIN)) {
		std::getline(std::cin, password);
	}
	else if (result == 0) {
		std::cout << "Timed out waiting for password\n";
	}
	else {
		std::cout << "Error waiting for password: " << stream_errno(errno);
	}

	return password;
}

auto to_little_endian(uint32_t value) -> std::array<uint8_t, sizeof(uint32_t)>
{
	std::array<uint8_t, sizeof(uint32_t)> bytes {};

	if (is_big_endian()) {
		bytes[0] = (value >> 24) & 0xff;
		bytes[1] = (value >> 16) & 0xff;
		bytes[2] = (value >> 8) & 0xff;
		bytes[3] = value & 0xff;
	}
	else {
		std::memcpy(bytes.data(), &value, sizeof(uint32_t));
	}

	return bytes;
}

auto from_little_endian(std::array<uint8_t, sizeof(uint32_t)> const& bytes) -> uint32_t
{
	uint32_t value {};

	if (is_big_endian()) {
		value |= bytes[0] << 24;
		value |= bytes[1] << 16;
		value |= bytes[2] << 8;
		value |= bytes[3];
	}
	else {
		std::memcpy(&value, bytes.data(), sizeof(uint32_t));
	}

	return value;
}

bool is_big_endian()
{
	// On a big endian machine, the first byte representing a 16-bit integer "0x0102" is 0x01
	// On a little endian machine, the first byte representing a 16-bit integer "0x0102" is 0x02
	static union
	{
		uint16_t value;
		uint8_t bytes[2];
	} value = {0x0102};

	return value.bytes[0] == 0x01;
}

/* ~~~~~~~~~~~~~~~~~
     Self Tests
~~~~~~~~~~~~~~~~~ */

/// Assumes a variable named "success" is in scope and initialized to true
#define assert_eq(a, b) \
	if ((a) != (b)) { \
		std::cout << "Assertion failed: " << (a) << " == " << (b) << '\n' \
		          << "            near: " << __FILE__ << ":" << __LINE__ << '\n'; \
		success = false; \
	}

template <typename Container>
std::ostream& stream(std::ostream& os, Container const& container)
{
	os << "[";
	for (auto const& item : container) {
		os << std::hex << std::setw(2) << std::setfill('0') << (int) item << std::dec << ' ';
	}
	os << "\b]";
	return os;
}

std::ostream& operator<<(std::ostream& os, std::vector<uint8_t> const& vec)
{
	return stream(os, vec);
}

std::ostream& operator<<(std::ostream& os, std::array<uint8_t, sizeof(uint32_t)> const& arr)
{
	return stream(os, arr);
}

bool test_split_hoststr()
{
	bool success = true;

	auto test = [&](std::string const& hoststr, std::string const& expected_host, uint16_t expected_port) {
		std::string host {};
		uint16_t port {};
		std::tie(host, port) = split_hoststr(hoststr);
		assert_eq(expected_host, host);
		assert_eq(expected_port, port);
	};

	test("name", "name", DEFAULT_RCON_PORT);
	test("name:27000", "name", 27000);
	test(":", "localhost", DEFAULT_RCON_PORT);
	test(":27000", "localhost", 27000);
	test("name:", "name", DEFAULT_RCON_PORT);

	return success;
}

bool test_to_little_endian()
{
	bool success = true;

	auto test = [&](uint32_t value, std::array<uint8_t, sizeof(uint32_t)> const& expected_bytes) {
		auto bytes = to_little_endian(value);
		assert_eq(expected_bytes, bytes);
	};

	test(0x01020304, {0x04, 0x03, 0x02, 0x01});

	return success;
}

bool test_from_little_endian()
{
	bool success = true;

	auto test = [&](std::array<uint8_t, sizeof(uint32_t)> const& bytes, uint32_t expected_value) {
		auto value = from_little_endian(bytes);
		assert_eq(expected_value, value);
	};

	test({0x04, 0x03, 0x02, 0x01}, 0x01020304);

	return success;
}

bool test_packet()
{
	bool success = true;

	auto test_size = [&](std::string const& body, uint32_t expected_size) {
		Packet packet(0);
		packet.set_body(body);
		assert_eq(expected_size, packet.size());
	};

	test_size("", 10);
	test_size("abcd", 14);

	auto test_to_byte_buffer = [&](std::string const& body, std::vector<uint8_t> const& expected_buffer) {
		Packet packet(0);
		packet.set_body(body);
		auto buffer = packet.to_byte_buffer();
		assert_eq(expected_buffer, buffer);
	};

	std::vector<uint8_t> expected {};
	//          size         id          type     body  null
	//          -----------  ----------  ----------  -  -
	expected = {10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
	test_to_byte_buffer("", expected);
	assert_eq(14, expected.size());

	//          size         id          type        body                   null
	//          -----------  ----------  ----------  ---------------------  -
	expected = {14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 'a', 'b', 'c', 'd', 0, 0};
	test_to_byte_buffer("abcd", expected);
	assert_eq(18, expected.size());

	return success;
}

bool test_id_generator()
{
	bool success = true;

	IdGenerator idgen {};

	auto test = [&](int expected_id) {
		auto id = idgen.generate();
		assert_eq(expected_id, id);
	};

	test(0);
	test(1);
	test(2);

	idgen.release(0);
	test(0);
	test(3);

	idgen.release(1);
	test(1);
	test(4);

	idgen.release(2);
	test(2);
	test(5);

	return success;
}

bool test()
{
	bool success = true;

	success &= test_split_hoststr();
	success &= test_to_little_endian();
	success &= test_from_little_endian();
	success &= test_id_generator();
	success &= test_packet();

	if (success) {
		std::cout << "All tests passed\n";
	}
	else {
		std::cout << "Some tests failed\n";
	}

	return success;
}
