Set<String> _qestoCommandLineArguments = const <String>{};

void setQestoCommandLineArguments(Iterable<String> arguments) {
  _qestoCommandLineArguments = Set<String>.unmodifiable(arguments);
}

bool hasQestoCommandLineArgument(String argument) =>
    _qestoCommandLineArguments.contains(argument);
