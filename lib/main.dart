import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import 'constants/enums.dart';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Circles NFT Contract',
      theme: ThemeData(
        primarySwatch: Colors.pink,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final CONTRACT_NAME = dotenv.env['CONTRACT_NAME'];
  final CONTRACT_ADDRESS = dotenv.env['CONTRACT_ADDRESS'];

  Mode _mode = Mode.none;

  http.Client httpClient = http.Client();
  late Web3Client polygonClient;
  int tokenCounter = -1;
  String tokenSymbol = '';
  final TextEditingController controller1 = TextEditingController();
  final TextEditingController controller2 = TextEditingController();

  Uint8List? mintedImage;
  int mintedCircleNo = 0;

  @override
  void initState() {
    final ALCHEMY_KEY = dotenv.env['ALCHEMY_KEY_TEST'];
    super.initState();
    httpClient = http.Client();
    polygonClient = Web3Client(ALCHEMY_KEY!, httpClient);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(CONTRACT_NAME!),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('\n Contract Address: '),
          Text(CONTRACT_ADDRESS!),
          FutureBuilder<String>(
            future: getTokenSymbol(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Text('\nToken symbol: ${snapshot.data}');
              } else {
                return const Text('\nToken symbol: wait...');
              }
            },
          ),
          FutureBuilder<int>(
              future: getTokenCounter(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  tokenCounter = snapshot.data!;
                  return Text('\nNumber of tokens: $tokenCounter');
                } else {
                  return const Text('\nNumber of tokens: wait....');
                }
              }),
          if (_mode == Mode.mint)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SizedBox(
                    width: MediaQuery.of(context).size.width * 0.3,
                    child: TextField(
                      controller: controller1,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          label: Text('Mint Circle Number')),
                    )),
                SizedBox(
                    width: MediaQuery.of(context).size.width * 0.3,
                    child: TextField(
                      controller: controller2,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(label: Text('to number')),
                    )),
              ],
            ),
          if (_mode == Mode.mint)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton(
                  child: const Text('Mint'),
                  onPressed: () async {
                    int from = int.parse(controller1.text);
                    int to = int.parse(controller2.text);
                    FocusManager.instance.primaryFocus?.unfocus();
                    int numberToMint = to >= from ? to - from + 1 : 0;
                    mintedCircleNo = from - 1;
                    mintStream(numberToMint, from).listen((dynamic event) {
                      setState(() {
                        mintedImage = event;
                        tokenCounter++;
                        mintedCircleNo++;
                      });
                    });
                  },
                )),
          Expanded(
              child: _mode == Mode.showNFTs
                  ? showNFTs(tokenCounter)
                  : showLatestMint())
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        onTap: (index) async {
          if (index == 0) {
            _mode = Mode.showNFTs;
            setState(() {});
          } else if (index == 1) {
            _mode = Mode.mint;
            FocusScope.of(context).unfocus();
            controller1.clear();
            controller2.clear();
            setState(() {});
          }
        },
        currentIndex: _mode.index > 0 ? _mode.index - 1 : 0,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.refresh), label: 'Show NFTs'),
          BottomNavigationBarItem(icon: Icon(Icons.ac_unit), label: 'Mint')
        ],
      ),
    );
  }

  Widget showNFTs(int tokenCounter) {
    return ListView.builder(
        itemCount: tokenCounter,
        itemBuilder: (_, int index) {
          return FutureBuilder<Map>(
              future: getImageFromToken(index),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  String json = snapshot.data!["json"];
                  int x = json.lastIndexOf('/');
                  int y = json.lastIndexOf('.json');
                  String imageName = json.substring(x + 1, y);
                  return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Image.memory(snapshot.data!["png"],
                              width: 50, height: 100),
                          Text('  Token number $index\n Image name $imageName')
                        ],
                      ));
                } else {
                  return const Text(
                      '\n\n\n   Retrieving image from IPFS ...\n\n\n');
                }
              });
        });
  }

  Widget showLatestMint() {
    if (mintedImage == null) {
      return Container();
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [Image.memory(mintedImage!, width: 50, height: 100)],
      );
    }
  }

  Future<DeployedContract> getContract() async {
    final CONTRACT_NAME = dotenv.env['CONTRACT_NAME'];
    final CONTRACT_ADDRESS = dotenv.env['CONTRACT_ADDRESS'];
    String abi = await rootBundle.loadString("assets/abi.json");
    DeployedContract contract = DeployedContract(
        ContractAbi.fromJson(abi, CONTRACT_NAME!),
        EthereumAddress.fromHex(CONTRACT_ADDRESS!));
    return contract;
  }

  Future<List<dynamic>> query(String functionName, List<dynamic> args) async {
    DeployedContract contract = await getContract();
    ContractFunction function = contract.function(functionName);

    List<dynamic> result = await polygonClient.call(
        contract: contract, function: function, params: args);
    return result;
  }

  Stream<dynamic> mintStream(int numberToMint, int firstCircleToMint) async* {
    final WALLET_PRIVATE_KEY = dotenv.env['WALLET_PRIVATE_KEY'];
    final JSON_CID = dotenv.env['JSON_CID'];

    EthPrivateKey credential = EthPrivateKey.fromHex(WALLET_PRIVATE_KEY!);
    DeployedContract contract = await getContract();
    ContractFunction function = contract.function('mint');

    for (int i = 0; i < numberToMint; i++) {
      String url = r'ipfs://' +
          JSON_CID! +
          r'/' +
          'Circle_${firstCircleToMint + i}.json';
      print('url to mint $url');
      var results = await Future.wait([
        getImageFromJson(url),
        polygonClient.sendTransaction(
            credential,
            Transaction.callContract(
                contract: contract, function: function, parameters: [url]),
            fetchChainIdFromNetworkId: true,
            chainId: null),
        Future.delayed(const Duration(seconds: 2))
      ]);
      yield results[0];
    }
  }

  Future<String> getTokenSymbol() async {
    if (tokenSymbol != '') {
      return tokenSymbol;
    } else {
      List<dynamic> result = await query('symbol', []);
      return result[0].toString();
    }
  }

  Future<int> getTokenCounter() async {
    if (tokenCounter >= 0) {
      return tokenCounter;
    } else {
      List<dynamic> result = await query('tokenCounter', []);
      return int.parse(result[0].toString());
    }
  }

  Future<Map> getImageFromToken(int token) async {
    List<dynamic> result = await query('tokenURI', [BigInt.from(token)]);
    String json = result[0];
    Uint8List png = await getImageFromJson(json);
    return {"png": png, "json": json};
  }

  Future<Uint8List> getImageFromJson(String json) async {
    final JSON_CID = dotenv.env['JSON_CID'];
    final IMAGES_CID = dotenv.env['IMAGES_CID'];

    String url = json
        .toString()
        // .replaceFirst(r'ipfs://', r'https://gateway.pinata.cloud/ipfs')
        .replaceFirst(JSON_CID!, IMAGES_CID!)
        .replaceFirst('.json', '.png');

    print("Url ::: $url");

    var isRedirect = true;
    http.Response resp;
    do {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['cookie'] = 'security=true';
      final streamresponse = await client.send(request);

      final response = await http.Response.fromStream(streamresponse);
      resp = response;

      if (response.statusCode == HttpStatus.movedTemporarily) {
        isRedirect = response.isRedirect;
        url = response.headers['location']!;
        print(response.headers);
        // final receivedCookies = response.headers['set-cookie'];
      } else if (response.statusCode == HttpStatus.ok) {}
    } while (isRedirect);

    return Uint8List.fromList(resp.body.codeUnits);

    // var resp = (await httpClient.get(Uri.parse(url)));
    //
    // // if (resp.statusCode != 200 ) {
    // //   print ("Url Get failed:: $url");
    // //   print(resp.body);
    // // }
  }
}
