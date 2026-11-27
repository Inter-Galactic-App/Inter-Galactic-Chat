import 'package:intergalactic/client/attachment.dart';
import 'package:matrix/matrix.dart';

class MatrixProcessedAttachment extends ProcessedAttachment {
  MatrixFile file;

  MatrixImageFile? thumbnailFile;

  bool spoiler;

  MatrixProcessedAttachment(this.file,
      {this.thumbnailFile, this.spoiler = false});
}
