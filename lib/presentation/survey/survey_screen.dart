// import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:livetrackingapp/presentation/component/utils.dart';
// import 'package:livetrackingapp/presentation/survey/survey_bloc.dart';
// import 'package:livetrackingapp/presentation/survey/survey_create_screen.dart';
// import 'package:livetrackingapp/presentation/survey/survey_detail_screen.dart';

// class SurveyScreen extends StatefulWidget {
//   final bool isAdmin;
  
//   const SurveyScreen({
//     Key? key,
//     this.isAdmin = false,
//   }) : super(key: key);

//   @override
//   State<SurveyScreen> createState() => _SurveyScreenState();
// }

// class _SurveyScreenState extends State<SurveyScreen> {
//   @override
//   void initState() {
//     super.initState();
//     context.read<SurveyBloc>().add(LoadActiveSurveys());
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(
//           'Survey',
//           style: semiBoldTextStyle(
//             size: 20,
//             color: Colors.white,
//           ),
//         ),
//         backgroundColor: kbpBlue900,
//         elevation: 0,
//         actions: [
//           // Hanya tampilkan tombol tambah survey untuk admin
//           if (widget.isAdmin)
//             IconButton(
//               icon: const Icon(Icons.add),
//               onPressed: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (context) => const SurveyCreateScreen(),
//                   ),
//                 ).then((_) {
//                   // Refresh data setelah kembali dari create screen
//                   context.read<SurveyBloc>().add(LoadActiveSurveys());
//                 });
//               },
//             ),
//         ],
//       ),
//       body: BlocBuilder<SurveyBloc, SurveyState>(
//         builder: (context, state) {
//           if (state is SurveyLoading) {
//             return const Center(
//               child: CircularProgressIndicator(),
//             );
//           } else if (state is ActiveSurveysLoaded) {
//             final surveys = state.surveys;
            
//             if (surveys.isEmpty) {
//               return Center(
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(
//                       Icons.assessment_outlined,
//                       size: 64,
//                       color: neutral400,
//                     ),
//                     const SizedBox(height: 16),
//                     Text(
//                       widget.isAdmin ? 'Belum ada survey dibuat' : 'Belum ada survey tersedia',
//                       style: semiBoldTextStyle(size: 18, color: neutral700),
//                       textAlign: TextAlign.center,
//                     ),
//                     const SizedBox(height: 8),
//                     Text(
//                       widget.isAdmin
//                           ? 'Klik tombol + untuk membuat survey baru'
//                           : 'Survey akan muncul di sini saat tersedia',
//                       style: regularTextStyle(size: 14, color: neutral600),
//                       textAlign: TextAlign.center,
//                     ),
//                     if (widget.isAdmin) ...[
//                       const SizedBox(height: 24),
//                       ElevatedButton.icon(
//                         onPressed: () {
//                           Navigator.push(
//                             context,
//                             MaterialPageRoute(
//                               builder: (context) => const SurveyCreateScreen(),
//                             ),
//                           ).then((_) {
//                             context.read<SurveyBloc>().add(LoadActiveSurveys());
//                           });
//                         },
//                         icon: const Icon(Icons.add),
//                         label: const Text('Buat Survey'),
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: kbpBlue900,
//                           padding: const EdgeInsets.symmetric(
//                             horizontal: 24,
//                             vertical: 12,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ],
//                 ),
//               );
//             }
            
//             return ListView.builder(
//               padding: const EdgeInsets.all(16),
//               itemCount: surveys.length,
//               itemBuilder: (context, index) {
//                 final survey = surveys[index];
//                 return _buildSurveyCard(context, survey, widget.isAdmin);
//               },
//             );
//           } else if (state is SurveyError) {
//             return Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Icon(
//                     Icons.error_outline,
//                     size: 64,
//                     color: dangerR500,
//                   ),
//                   const SizedBox(height: 16),
//                   Text(
//                     'Terjadi Kesalahan',
//                     style: semiBoldTextStyle(size: 18, color: dangerR700),
//                     textAlign: TextAlign.center,
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     state.message,
//                     style: regularTextStyle(size: 14, color: neutral700),
//                     textAlign: TextAlign.center,
//                   ),
//                   const SizedBox(height: 24),
//                   ElevatedButton(
//                     onPressed: () {
//                       context.read<SurveyBloc>().add(LoadActiveSurveys());
//                     },
//                     child: const Text('Coba Lagi'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: kbpBlue900,
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 24,
//                         vertical: 12,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           }
//           return const Center(child: CircularProgressIndicator());
//         },
//       ),
//       // Floating action button untuk admin
//       floatingActionButton: widget.isAdmin
//           ? FloatingActionButton(
//               onPressed: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (context) => const SurveyCreateScreen(),
//                   ),
//                 ).then((_) {
//                   context.read<SurveyBloc>().add(LoadActiveSurveys());
//                 });
//               },
//               backgroundColor: kbpBlue900,
//               child: const Icon(Icons.add),
//             )
//           : null,
//     );
//   }

//   Widget _buildSurveyCard(BuildContext context, Survey survey, bool isAdmin) {
//     // Format tanggal untuk ditampilkan
//     final dateFormat = DateFormat('dd MMM yyyy');
//     final expiredText = survey.isExpired 
//         ? ' (Kadaluarsa)' 
//         : '';
    
//     return Card(
//       margin: const EdgeInsets.only(bottom: 12),
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(12),
//       ),
//       elevation: 2,
//       child: InkWell(
//         onTap: () {
//           // Navigasi ke detail survey
//           Navigator.push(
//             context,
//             MaterialPageRoute(
//               builder: (context) => SurveyDetailScreen(
//                 surveyId: survey.id,
//                 isAdmin: isAdmin,
//               ),
//             ),
//           );
//         },
//         borderRadius: BorderRadius.circular(12),
//         child: Padding(
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Expanded(
//                     child: Text(
//                       survey.title,
//                       style: semiBoldTextStyle(size: 16),
//                       maxLines: 2,
//                       overflow: TextOverflow.ellipsis,
//                     ),
//                   ),
//                   if (isAdmin) ...[
//                     IconButton(
//                       icon: Icon(
//                         Icons.edit,
//                         color: kbpBlue700,
//                         size: 20,
//                       ),
//                       onPressed: () {
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (context) => SurveyCreateScreen(
//                               survey: survey,
//                             ),
//                           ),
//                         ).then((_) {
//                           context.read<SurveyBloc>().add(LoadActiveSurveys());
//                         });
//                       },
//                       constraints: const BoxConstraints(),
//                       padding: const EdgeInsets.all(8),
//                       tooltip: 'Edit Survey',
//                     ),
//                     IconButton(
//                       icon: Icon(
//                         Icons.delete,
//                         color: dangerR500,
//                         size: 20,
//                       ),
//                       onPressed: () {
//                         // Konfirmasi hapus survey
//                         showDialog(
//                           context: context,
//                           builder: (context) => AlertDialog(
//                             title: Text(
//                               'Hapus Survey?',
//                               style: semiBoldTextStyle(size: 18),
//                             ),
//                             content: Text(
//                               'Survey "${survey.title}" akan dihapus secara permanen. Tindakan ini tidak dapat dibatalkan.',
//                               style: regularTextStyle(),
//                             ),
//                             actions: [
//                               TextButton(
//                                 onPressed: () => Navigator.pop(context),
//                                 child: Text(
//                                   'Batal',
//                                   style: mediumTextStyle(color: neutral700),
//                                 ),
//                               ),
//                               ElevatedButton(
//                                 onPressed: () {
//                                   Navigator.pop(context);
//                                   context.read<SurveyBloc>().add(DeleteSurvey(survey.id));
//                                 },
//                                 style: ElevatedButton.styleFrom(
//                                   backgroundColor: dangerR500,
//                                   foregroundColor: Colors.white,
//                                 ),
//                                 child: Text(
//                                   'Hapus',
//                                   style: semiBoldTextStyle(color: Colors.white),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         );
//                       },
//                       constraints: const BoxConstraints(),
//                       padding: const EdgeInsets.all(8),
//                       tooltip: 'Hapus Survey',
//                     ),
//                   ],
//                 ],
//               ),
//               if (survey.description.isNotEmpty) ...[
//                 const SizedBox(height: 8),
//                 Text(
//                   survey.description,
//                   style: regularTextStyle(color: neutral700),
//                   maxLines: 2,
//                   overflow: TextOverflow.ellipsis,
//                 ),
//               ],
//               const SizedBox(height: 12),
//               Row(
//                 children: [
//                   Icon(
//                     Icons.help_outline,
//                     size: 16,
//                     color: neutral600,
//                   ),
//                   const SizedBox(width: 4),
//                   Text(
//                     '${survey.questions.length} pertanyaan',
//                     style: regularTextStyle(size: 12, color: neutral600),
//                   ),
//                   const SizedBox(width: 16),
//                   Icon(
//                     Icons.calendar_today,
//                     size: 16,
//                     color: neutral600,
//                   ),
//                   const SizedBox(width: 4),
//                   Text(
//                     'Sampai ${dateFormat.format(survey.expiresAt)}$expiredText',
//                     style: regularTextStyle(
//                       size: 12, 
//                       color: survey.isExpired ? dangerR500 : neutral600
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 12),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   // Status survey
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 12,
//                       vertical: 6,
//                     ),
//                     decoration: BoxDecoration(
//                       color: survey.isExpired
//                           ? dangerR100
//                           : (survey.isActive ? successG100 : neutral200),
//                       borderRadius: BorderRadius.circular(16),
//                     ),
//                     child: Text(
//                       survey.isExpired
//                           ? 'Kadaluarsa'
//                           : (survey.isActive ? 'Aktif' : 'Tidak Aktif'),
//                       style: mediumTextStyle(
//                         size: 12,
//                         color: survey.isExpired
//                             ? dangerR700
//                             : (survey.isActive ? successG700 : neutral700),
//                       ),
//                     ),
//                   ),
                  
//                   // Tombol lihat survey
//                   ElevatedButton(
//                     onPressed: () {
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (context) => SurveyDetailScreen(
//                             surveyId: survey.id,
//                             isAdmin: isAdmin,
//                           ),
//                         ),
//                       );
//                     },
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: kbpBlue900,
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 16,
//                         vertical: 8,
//                       ),
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                     ),
//                     child: Text(
//                       isAdmin ? 'Lihat Hasil' : 'Isi Survey',
//                       style: mediumTextStyle(size: 12, color: Colors.white),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }