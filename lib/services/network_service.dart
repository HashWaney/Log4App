import 'dart:io';

class NetworkService {
  Future<List<String>> getLanIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    final candidates = <_AddressCandidate>[];

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!_isPrivateIpv4(address.address)) continue;
        candidates.add(
          _AddressCandidate(
            address: address.address,
            interfaceName: interface.name,
            score: _score(interface.name, address.address),
          ),
        );
      }
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.address.compareTo(b.address);
    });

    return candidates.map((e) => e.address).toSet().toList();
  }

  Future<String?> getPrimaryLanIpv4Address() async {
    final addresses = await getLanIpv4Addresses();
    return addresses.isEmpty ? null : addresses.first;
  }

  int _score(String interfaceName, String address) {
    final name = interfaceName.toLowerCase();
    var score = 0;

    if (name == 'en0' || name == 'en1') score += 80;
    if (name.contains('wi-fi') ||
        name.contains('wifi') ||
        name.contains('wlan') ||
        name.contains('wireless')) {
      score += 70;
    }
    if (name.contains('ethernet') ||
        name.startsWith('eth') ||
        name.startsWith('en')) {
      score += 50;
    }

    const lowPriority = <String>[
      'utun',
      'tun',
      'tap',
      'vpn',
      'docker',
      'vbox',
      'vmnet',
      'bridge',
      'awdl',
      'llw',
    ];
    if (lowPriority.any(name.contains)) score -= 120;

    if (address.startsWith('192.168.')) score += 30;
    if (address.startsWith('172.')) score += 25;
    if (address.startsWith('10.')) score += 20;

    return score;
  }

  bool _isPrivateIpv4(String value) {
    final raw = value.split('.');
    if (raw.length != 4) return false;
    final parts = raw.map(int.tryParse).toList();
    if (parts.any((e) => e == null)) return false;

    final a = parts[0]!;
    final b = parts[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }
}

class _AddressCandidate {
  const _AddressCandidate({
    required this.address,
    required this.interfaceName,
    required this.score,
  });

  final String address;
  final String interfaceName;
  final int score;
}
