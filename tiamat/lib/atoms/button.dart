import 'package:flutter/material.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

@UseCase(name: 'Default', type: Button)
Widget wbButton(BuildContext context) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(width: 200, height: 50, child: Center(child: Button())),
        SizedBox(
          width: 200,
          height: 50,
          child: Center(child: Button.secondary()),
        ),
        SizedBox(
          width: 200,
          height: 50,
          child: Center(child: Button.success()),
        ),
        SizedBox(width: 200, height: 50, child: Center(child: Button.danger())),
        SizedBox(
          width: 200,
          height: 50,
          child: Center(child: Button.critical()),
        ),
        SizedBox(
          width: 200,
          height: 50,
          child: Center(child: Button(isLoading: true)),
        ),
      ],
    ),
  );
}

enum ButtonType { primary, secondary, success, danger, critical }

class Button extends StatelessWidget {
  const Button({
    super.key,
    this.text = "Hello, World!",
    this.onTap,
    this.isLoading,
    this.type = ButtonType.primary,
  });
  final ButtonType type;
  final String text;
  final Function? onTap;
  final bool? isLoading;

  const Button.secondary({
    Key? key,
    this.text = "Hello, World!",
    this.onTap,
    this.isLoading,
  })  : type = ButtonType.secondary,
        super(key: key);

  const Button.success({
    Key? key,
    this.text = "Hello, World!",
    this.onTap,
    this.isLoading,
  })  : type = ButtonType.success,
        super(key: key);

  const Button.danger({
    Key? key,
    this.text = "Hello, World!",
    this.onTap,
    this.isLoading,
  })  : type = ButtonType.danger,
        super(key: key);

  const Button.critical({
    Key? key,
    this.text = "Hello, World!",
    this.onTap,
    this.isLoading,
  })  : type = ButtonType.critical,
        super(key: key);

  @override
  Widget build(BuildContext context) {
    ButtonStyle style;
    final elevatedStyle =
        Theme.of(context).elevatedButtonTheme.style ?? const ButtonStyle();

    switch (type) {
      case ButtonType.primary:
        style = elevatedStyle.copyWith(
          foregroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.onPrimary,
          ),
          backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.primary,
          ),
        );
        break;
      case ButtonType.secondary:
        style = elevatedStyle.copyWith(
          foregroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.secondaryContainer,
          ),
        );
        break;
      case ButtonType.success:
        style = elevatedStyle.copyWith(
          foregroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.onTertiaryContainer,
          ),
          backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.tertiaryContainer,
          ),
        );

        break;
      case ButtonType.danger:
        style = elevatedStyle.copyWith(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(
            BorderSide(color: Theme.of(context).colorScheme.error, width: 1),
          ),
        );
        break;
      case ButtonType.critical:
        style = elevatedStyle.copyWith(
          backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.error,
          ),
        );
        break;
    }

    return ElevatedButton(
      style: style,
      onPressed: isLoading == true
          ? null
          : () {
              onTap?.call();
            },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: isLoading == true
            ? makeLoadingIndicator(context, style.foregroundColor?.resolve({}))
            : tiamat.Text(text, color: style.foregroundColor?.resolve({})),
      ),
    );
  }

  Widget makeLoadingIndicator(BuildContext context, Color? color) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0, child: tiamat.Text.label(text)),
        SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
